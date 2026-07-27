package service

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"cn.meow/meowtv/internal/model/entity"
)

func (s *DownloadService) worker() {
	defer s.wg.Done()
	for {
		select {
		case <-s.stopCh:
			return
		case taskID := <-s.taskQueue:
			s.activeCount.Add(1)
			s.executeTask(taskID)
			s.activeCount.Add(-1)
		}
	}
}

func (s *DownloadService) recoverPendingTasks() {
	time.Sleep(2 * time.Second)
	for _, st := range []entity.DownloadStatus{
		entity.DownloadStatusQueued, entity.DownloadStatusParsing,
		entity.DownloadStatusDownloading, entity.DownloadStatusMerging,
	} {
		si := int(st)
		tasks, err := s.repo.ListAll(&si, 1000, 0)
		if err != nil {
			continue
		}
		for _, t := range tasks {
			_ = s.repo.UpdateStatus(t.ID, entity.DownloadStatusQueued, "")
			s.taskQueue <- t.ID
			slog.Info("recovered pending task", "task_id", t.ID)
		}
	}
}

// executeTask 执行单个下载任务完整流程
func (s *DownloadService) executeTask(taskID int64) {
	task, err := s.repo.GetByID(taskID)
	if err != nil {
		slog.Error("get download task failed", "task_id", taskID, "error", err)
		return
	}
	if task.Status == entity.DownloadStatusCancelled || task.Status == entity.DownloadStatusCompleted {
		return
	}

	ctx, cancel := context.WithCancel(context.Background())
	s.cancelFuncs.Store(taskID, cancel)
	defer func() {
		cancel()
		s.cancelFuncs.Delete(taskID)
	}()

	// 1. 解析 m3u8
	_ = s.repo.UpdateStatus(taskID, entity.DownloadStatusParsing, "")
	m3u8Info, err := s.parser.Parse(task.M3u8URL)
	if err != nil {
		s.failTask(taskID, fmt.Sprintf("解析m3u8失败: %v", err))
		return
	}

	task.TotalSegments = len(m3u8Info.Segments)
	_ = s.repo.Update(task)

	if ctx.Err() != nil {
		return
	}

	// 2. 下载分片
	_ = s.repo.UpdateStatus(taskID, entity.DownloadStatusDownloading, "")

	tmpDir := filepath.Join(s.getDownloadDir(), "tmp", strconv.FormatInt(taskID, 10))
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		s.failTask(taskID, fmt.Sprintf("创建临时目录失败: %v", err))
		return
	}
	defer os.RemoveAll(tmpDir)

	downloadedCount, err := s.downloadSegments(ctx, m3u8Info, tmpDir, taskID)
	if err != nil {
		if ctx.Err() != nil {
			_ = s.repo.UpdateStatus(taskID, entity.DownloadStatusCancelled, "")
			return
		}
		s.failTask(taskID, fmt.Sprintf("下载分片失败: %v", err))
		return
	}

	// 3. 合并 + 转封装
	_ = s.repo.UpdateStatus(taskID, entity.DownloadStatusMerging, "")

	// 防御性检查：即使 Start() 时通过，运行期间 ffmpeg 也可能被卸载
	if !s.ffmpegAvailable {
		s.failTask(taskID, "ffmpeg 不可用，无法将 TS 转封装为 MP4。请安装 ffmpeg 后重试。")
		return
	}

	outputDir := filepath.Join(s.getDownloadDir(), sanitizeFilename(task.VodName))
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		s.failTask(taskID, fmt.Sprintf("创建输出目录失败: %v", err))
		return
	}

	mp4Path := filepath.Join(outputDir, sanitizeFilename(task.EpName)+".mp4")
	tsPath := filepath.Join(outputDir, sanitizeFilename(task.EpName)+".ts")
	var outputPath string
	var fileSize int64

	// 策略 1（首选）：流式拼接 TS 文件，然后单文件 remux
	// 这种方式最稳定，不依赖 ffmpeg concat demuxer，不会触发 segfault
	slog.Info("merging segments: stream concat ts", "task_id", taskID, "segments", downloadedCount)
	if err := streamConcatTS(tmpDir, downloadedCount, tsPath); err != nil {
		s.failTask(taskID, fmt.Sprintf("流式拼接 TS 文件失败: %v", err))
		return
	}

	if fi, statErr := os.Stat(tsPath); statErr == nil {
		fileSize = fi.Size()
		slog.Info("stream concat ts success, size_mb", "task_id", taskID, "size_mb", fileSize/1024/1024)
	}

	// 尝试 remux TS to MP4（单文件 remux 比 concat demuxer 更稳定）
	if result, remuxErr := remuxToMP4(tsPath, mp4Path); remuxErr == nil {
		_ = os.Remove(tsPath)
		outputPath = result
		if fi, statErr := os.Stat(outputPath); statErr == nil {
			fileSize = fi.Size()
		}
		slog.Info("stream concat remux to mp4 success", "task_id", taskID, "file", outputPath,
			"size_mb", fileSize/1024/1024)
	} else {
		// 策略 2（备选）：ffmpeg concat demuxer 一步合并+remux
		slog.Warn("stream concat remux failed, trying concat demuxer", "task_id", taskID, "error", remuxErr)

		// 生成 ffmpeg concat list（使用绝对路径）
		concatListPath, listErr := generateConcatList(tmpDir, downloadedCount)
		if listErr != nil {
			s.failTask(taskID, fmt.Sprintf("生成 concat list 失败: %v", listErr))
			return
		}

		// 尝试 concat demuxer + remux
		if result, concatErr := concatRemuxToMP4(concatListPath, mp4Path); concatErr == nil {
			// concat demuxer 成功，删除临时 TS 文件
			_ = os.Remove(tsPath)
			outputPath = result
			if fi, statErr := os.Stat(outputPath); statErr == nil {
				fileSize = fi.Size()
			}
			slog.Info("concat demuxer remux to mp4 success", "task_id", taskID, "file", outputPath,
				"segments", downloadedCount, "size_mb", fileSize/1024/1024)
		} else {
			// 策略 3（保底）：保留 TS 文件
			slog.Warn("concat demuxer remux also failed, keeping ts file", "task_id", taskID,
				"stream_remux_error", remuxErr, "concat_remux_error", concatErr)
			outputPath = tsPath
			if fi, statErr := os.Stat(tsPath); statErr == nil {
				fileSize = fi.Size()
			}
		}
	}

	// 5. 标记完成
	_ = s.repo.UpdateCompleted(taskID, outputPath, fileSize)
	slog.Info("download task completed", "task_id", taskID, "file", outputPath,
		"size_mb", fileSize/1024/1024)
}

// failTask 标记任务失败
func (s *DownloadService) failTask(taskID int64, errMsg string) {
	slog.Error("download task failed", "task_id", taskID, "error", errMsg)
	_ = s.repo.UpdateStatus(taskID, entity.DownloadStatusFailed, errMsg)
}

// downloadSegments 并发下载所有分片，将每个分片写入独立文件（为 ffmpeg concat demuxer 准备）
func (s *DownloadService) downloadSegments(ctx context.Context, info *M3u8Info, tmpDir string, taskID int64) (int, error) {
	total := len(info.Segments)
	if total == 0 {
		return 0, fmt.Errorf("no segments to download")
	}

	segConcurrency := s.getSegmentConcurrency()
	if segConcurrency > total {
		segConcurrency = total
	}

	var mu sync.Mutex
	var downloaded int
	var downloadErr error

	sem := make(chan struct{}, segConcurrency)
	var wg sync.WaitGroup

	for i, seg := range info.Segments {
		if ctx.Err() != nil {
			return downloaded, ctx.Err()
		}

		sem <- struct{}{} // 获取信号量
		wg.Add(1)

		go func(idx int, seg SegmentInfo) {
			defer func() {
				// goroutine recovery 保护：防止任何未捕获的 panic 导致整个系统崩溃
				if r := recover(); r != nil {
					mu.Lock()
					slog.Error("segment goroutine panic recovered",
						"segment", idx,
						"panic", r,
						"url", seg.URL)
					if downloadErr == nil {
						downloadErr = fmt.Errorf("segment %d: panic recovered: %v", idx, r)
					}
					mu.Unlock()
				}
				<-sem
			}()
			defer wg.Done()

			// 优先使用分片级加密信息，回退到全局加密信息
			enc := seg.Encryption
			if enc == nil {
				enc = info.Encryption
			}

			data, err := s.downloadOneSegment(ctx, seg.URL, enc, idx)
			if err != nil {
				mu.Lock()
				if downloadErr == nil {
					downloadErr = fmt.Errorf("segment %d: %w", idx, err)
				}
				mu.Unlock()
				return
			}

			// 写入独立的分片文件（格式：seg_0000.ts, seg_0001.ts, ...）
			segPath := filepath.Join(tmpDir, fmt.Sprintf("seg_%04d.ts", idx))
			if err := os.WriteFile(segPath, data, 0644); err != nil {
				mu.Lock()
				if downloadErr == nil {
					downloadErr = fmt.Errorf("segment %d: write file failed: %w", idx, err)
				}
				mu.Unlock()
				return
			}

			mu.Lock()
			downloaded++
			progress := float64(downloaded) / float64(total) * 100
			mu.Unlock()

			_ = s.repo.UpdateProgress(taskID, downloaded, progress)
		}(i, seg)
	}

	wg.Wait()

	if downloadErr != nil {
		return downloaded, downloadErr
	}
	return downloaded, nil
}

// downloadOneSegment 下载单个 TS 分片（支持 AES-128 解密，含重试机制）
// 薄包装：调用公共函数 DownloadOneSegment
func (s *DownloadService) downloadOneSegment(ctx context.Context, segURL string, enc *EncryptionInfo, segIndex int) ([]byte, error) {
	return DownloadOneSegment(ctx, s.httpClient, segURL, enc, segIndex)
}

// doDownloadSegment 执行单次分片下载（不含重试逻辑）
// 薄包装：调用公共函数 DoDownloadSegment
func (s *DownloadService) doDownloadSegment(ctx context.Context, segURL string, enc *EncryptionInfo, segIndex int) ([]byte, error) {
	return DoDownloadSegment(ctx, s.httpClient, segURL, enc, segIndex)
}

// isRetryableError 已迁移到 segment_downloader.go 作为公共函数 IsRetryableError
// DownloadService 使用公共函数 DownloadOneSegment，间接调用 IsRetryableError

// ── 配置读取辅助 ──────────────────────────────────────────────────────────

func (s *DownloadService) getDownloadDir() string {
	cfg := s.configService.GetValue(context.Background(), configKeyDownload)
	if cfg == nil || cfg.Value1 == "" {
		return downloadDirDefault
	}
	return cfg.Value1
}

func (s *DownloadService) getMaxConcurrent() int {
	cfg := s.configService.GetValue(context.Background(), configKeyDownload)
	if cfg == nil || cfg.Value2 == "" {
		return maxConcurrentDefault
	}
	n, err := strconv.Atoi(cfg.Value2)
	if err != nil || n < 1 {
		return maxConcurrentDefault
	}
	return n
}

func (s *DownloadService) getSegmentConcurrency() int {
	cfg := s.configService.GetValue(context.Background(), configKeyDownload)
	if cfg == nil || cfg.Value3 == "" {
		return segmentConcurrencyDefault
	}
	n, err := strconv.Atoi(cfg.Value3)
	if err != nil || n < 1 {
		return segmentConcurrencyDefault
	}
	return n
}

// sanitizeFilename 清理文件名中的非法字符
func sanitizeFilename(name string) string {
	if name == "" {
		return "unnamed"
	}
	// 移除/替换不安全字符
	reg := regexp.MustCompile(`[<>:"/\\|?*]`)
	name = reg.ReplaceAllString(name, "_")
	name = strings.TrimSpace(name)
	if len(name) > 200 {
		name = name[:200]
	}
	return name
}

// generateConcatList 生成 ffmpeg concat demuxer 所需的 list 文件
// 使用绝对路径避免 ffmpeg 工作目录问题
func generateConcatList(tmpDir string, count int) (string, error) {
	listPath := filepath.Join(tmpDir, "concat.txt")
	var lines []string
	for i := 0; i < count; i++ {
		segPath := filepath.Join(tmpDir, fmt.Sprintf("seg_%04d.ts", i))
		absPath, err := filepath.Abs(segPath)
		if err != nil {
			return "", fmt.Errorf("get absolute path for segment %d: %w", i, err)
		}
		lines = append(lines, fmt.Sprintf("file '%s'", absPath))
	}
	return listPath, os.WriteFile(listPath, []byte(strings.Join(lines, "\n")+"\n"), 0644)
}

// concatRemuxToMP4 使用 ffmpeg concat demuxer 合并多个 TS 文件并转封装为 MP4（一步完成）
// 返回 MP4 文件路径；如果 ffmpeg 不可用或失败则返回错误
func concatRemuxToMP4(concatListPath, mp4Path string) (string, error) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		return "", fmt.Errorf("ffmpeg not found: %w", err)
	}

	// 如果目标 MP4 已存在，先删除
	_ = os.Remove(mp4Path)

	// ffmpeg -f concat -safe 0 -i concat.txt -fflags +genpts -avoid_negative_ts make_zero -c copy -movflags +faststart output.mp4
	cmd := exec.Command("ffmpeg",
		"-y",           // 覆盖输出
		"-f", "concat", // 使用 concat demuxer
		"-safe", "0", // 允许相对路径
		"-i", concatListPath, // concat list 文件
		"-err_detect", "ignore_err", // 忽略输入流中的错误检测，提高鲁棒性
		"-fflags", "+genpts+discardcorrupt", // 生成缺失的 PTS 时间戳，丢弃损坏帧
		"-avoid_negative_ts", "make_zero", // 将负时间戳偏移到 0
		"-c", "copy", // 不重编码，仅转封装
		"-movflags", "+faststart", // moov atom 前置，支持流式播放和 Range seek
		mp4Path,
	)

	// 设置超时（大文件需要更长时间）
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd = exec.CommandContext(ctx, cmd.Args[0], cmd.Args[1:]...)

	output, err := cmd.CombinedOutput()
	if err != nil {
		// 清理可能生成的不完整 MP4 文件
		_ = os.Remove(mp4Path)
		return "", fmt.Errorf("ffmpeg concat remux failed: %w, output: %s", err, string(output))
	}

	// 验证输出文件存在且大小合理
	info, err := os.Stat(mp4Path)
	if err != nil {
		return "", fmt.Errorf("mp4 file not found after concat remux: %w", err)
	}
	if info.Size() == 0 {
		_ = os.Remove(mp4Path)
		return "", fmt.Errorf("mp4 file is empty after concat remux")
	}

	return mp4Path, nil
}

// remuxToMP4 使用 ffmpeg 将 TS 文件转封装为 MP4（remux，不重编码，速度极快）
// 返回 MP4 文件路径；如果 ffmpeg 不可用或转封装失败则返回错误
func remuxToMP4(tsPath, mp4Path string) (string, error) {
	// 检查 ffmpeg 是否可用
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		return "", fmt.Errorf("ffmpeg not found: %w", err)
	}

	// 如果目标 MP4 已存在，先删除
	_ = os.Remove(mp4Path)

	// ffmpeg -i input.ts -fflags +genpts -avoid_negative_ts make_zero -c copy -movflags +faststart output.mp4
	cmd := exec.Command("ffmpeg",
		"-y",         // 覆盖输出
		"-i", tsPath, // 输入 TS 文件
		"-fflags", "+genpts", // 生成缺失的 PTS 时间戳
		"-avoid_negative_ts", "make_zero", // 将负时间戳偏移到 0
		"-c", "copy", // 不重编码，仅转封装
		"-movflags", "+faststart", // moov atom 前置，支持流式播放和 Range seek
		mp4Path,
	)

	// 设置超时（大文件需要更长时间）
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd = exec.CommandContext(ctx, cmd.Args[0], cmd.Args[1:]...)

	output, err := cmd.CombinedOutput()
	if err != nil {
		// 清理可能生成的不完整 MP4 文件
		_ = os.Remove(mp4Path)
		return "", fmt.Errorf("ffmpeg remux failed: %w, output: %s", err, string(output))
	}

	// 验证输出文件存在且大小合理
	info, err := os.Stat(mp4Path)
	if err != nil {
		return "", fmt.Errorf("mp4 file not found after remux: %w", err)
	}
	if info.Size() == 0 {
		_ = os.Remove(mp4Path)
		return "", fmt.Errorf("mp4 file is empty after remux")
	}

	return mp4Path, nil
}

// streamConcatTS 流式拼接多个 TS 分片文件为单个 TS 文件
// 使用 io.Copy 流式复制，内存占用恒定，不会 OOM
// 如果 m3u8Info 不为 nil 且包含加密信息，合并时会先解密每个分片
func streamConcatTS(tmpDir string, count int, tsPath string, m3u8Info ...*M3u8Info) error {
	out, err := os.Create(tsPath)
	if err != nil {
		return fmt.Errorf("create ts file: %w", err)
	}
	defer out.Close()

	// 获取加密信息（可选参数）
	var info *M3u8Info
	if len(m3u8Info) > 0 {
		info = m3u8Info[0]
	}

	for i := 0; i < count; i++ {
		segPath := filepath.Join(tmpDir, fmt.Sprintf("seg_%04d.ts", i))
		data, err := os.ReadFile(segPath)
		if err != nil {
			return fmt.Errorf("read segment %d: %w", i, err)
		}
		if len(data) == 0 {
			return fmt.Errorf("segment %d is empty", i)
		}

		// 如果有加密信息，解密分片
		if info != nil {
			decrypted, decryptErr := decryptSegmentData(data, i, info)
			if decryptErr != nil {
				slog.Warn("failed to decrypt segment during concat, using raw data",
					"segment", i, "error", decryptErr)
			} else {
				data = decrypted
			}
		}

		written, err := out.Write(data)
		if err != nil {
			return fmt.Errorf("write segment %d: %w", i, err)
		}
		if written == 0 {
			return fmt.Errorf("segment %d wrote 0 bytes", i)
		}
	}
	return nil
}

// decryptSegmentData 解密单个分片数据
// 根据分片索引查找对应的加密信息，优先使用分片级加密，回退到全局加密
func decryptSegmentData(data []byte, segIndex int, m3u8Info *M3u8Info) ([]byte, error) {
	var enc *EncryptionInfo

	// 优先使用分片级加密信息
	if segIndex < len(m3u8Info.Segments) {
		enc = m3u8Info.Segments[segIndex].Encryption
	}
	// 回退到全局加密信息
	if enc == nil {
		enc = m3u8Info.Encryption
	}

	// 没有加密信息或非 AES-128，直接返回原始数据
	if enc == nil || enc.Method != "AES-128" || len(enc.Key) == 0 {
		return data, nil
	}

	// 计算 IV
	iv := enc.IV
	if len(iv) == 0 {
		// 使用分片序号作为 IV
		iv = make([]byte, 16)
		iv[15] = byte(segIndex)
	}

	decrypted, err := DecryptSegment(data, enc.Key, iv)
	if err != nil {
		// 解密失败：检查原始数据是否为未加密的 TS 流
		if IsTSPacketData(data) {
			return data, nil
		}
		return nil, fmt.Errorf("decrypt segment %d: %w", segIndex, err)
	}

	return decrypted, nil
}

// CheckFFmpeg 检测 ffmpeg 是否可用，返回 (available, path, version)
func CheckFFmpeg() (bool, string, string) {
	p, err := exec.LookPath("ffmpeg")
	if err != nil {
		return false, "", ""
	}
	cmd := exec.Command("ffmpeg", "-version")
	output, err := cmd.Output()
	if err != nil {
		return true, p, "unknown"
	}
	// 取第一行，如 "ffmpeg version 6.0 ..."
	line := strings.SplitN(string(output), "\n", 2)[0]
	return true, p, line
}
