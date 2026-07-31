package service

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

// DemoDomain 虚拟本地资源站点的 domain 标识
const DemoDomain = "local_demo_domain"

// DemoUserID 本地 demo 数据关联的特殊用户 ID（0 表示无归属用户）
// GetTaskFilePath 在 demo 模式下会跳过 UserID 校验
const DemoUserID int64 = 0

// 视频文件扩展名白名单
var videoExts = map[string]bool{
	".mp4": true, ".mkv": true, ".avi": true, ".mov": true,
	".m4v": true, ".ts": true, ".flv": true, ".webm": true,
}

// 图片文件扩展名白名单（用于封面关联）
var imageExts = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".webp": true,
}

// LocalDataService 本地数据扫描与入库服务（Apple Store 审核演示模式）
type LocalDataService struct {
	localVideoRepo *repository.LocalVideoRepository
	downloadRepo   *repository.DownloadRepository
	sysConfigRepo  repository.SysConfigRepository
	localDataDir   string
}

// NewLocalDataService 创建本地数据服务
func NewLocalDataService(
	localVideoRepo *repository.LocalVideoRepository,
	downloadRepo *repository.DownloadRepository,
	sysConfigRepo repository.SysConfigRepository,
	localDataDir string,
) *LocalDataService {
	return &LocalDataService{
		localVideoRepo: localVideoRepo,
		downloadRepo:   downloadRepo,
		sysConfigRepo:  sysConfigRepo,
		localDataDir:   localDataDir,
	}
}

// IsDemoMode 判断是否启用了 demo 模式
func (s *LocalDataService) IsDemoMode() bool {
	return s.localDataDir != ""
}

// ScanAndSeed 扫描本地数据目录并入库（启动时调用）
// 流程：
//  1. 递归扫描目录，收集视频文件和封面图片
//  2. 为每个视频文件创建 download_task（status=Completed）用于播放
//  3. 将视频信息映射为 MacCMS 结构写入 local_video 表
//  4. 写入虚拟资源站点配置到 sys_config
func (s *LocalDataService) ScanAndSeed(ctx context.Context) error {
	if !s.IsDemoMode() {
		return nil
	}

	absDir, err := filepath.Abs(s.localDataDir)
	if err != nil {
		return fmt.Errorf("resolve demo data dir absolute path failed: %w", err)
	}

	slog.Info("starting demo data scan", "dir", absDir)

	// 检查目录是否存在
	info, err := os.Stat(absDir)
	if err != nil {
		return fmt.Errorf("demo data dir not accessible: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("demo data dir is not a directory: %s", absDir)
	}

	// 1. 扫描收集视频条目
	entries := s.scanDirectory(absDir)
	if len(entries) == 0 {
		slog.Warn("no video files found in demo data dir", "dir", absDir)
		// 仍然写入虚拟站点配置，保证站点存在
		return s.ensureDemoSiteConfig(ctx)
	}

	// 2. 清理旧的 demo download_task 记录（status=Completed 且 resource_domain=local_demo_domain）
	if err := s.clearOldDemoTasks(); err != nil {
		slog.Warn("failed to clear old demo download tasks", "error", err)
	}

	// 3. 为每个视频创建 download_task 并构建 local_video 记录
	videos := make([]entity.LocalVideo, 0, len(entries))
	for i, entry := range entries {
		vodID := int64(i + 1)

		// 创建 download_task 记录（status=Completed，FilePath=本地视频绝对路径）
		// VodID 填入 local_video 的 vod_id，使 checkDownload 能按 vod_id 匹配到 demo task
		taskID, err := s.createDemoTask(entry, vodID)
		if err != nil {
			slog.Error("failed to create demo download task",
				"vod_name", entry.Title, "file", entry.FilePath, "error", err)
			continue
		}

		// 构建 vod_play_url：MacCMS 标准格式 "剧集名$播放地址#"
		// vod_play_from 已单独提供播放源名（local），因此 vod_play_url 仅包含剧集段。
		// URL 末尾追加 .mp4 伪扩展，使前端 parsePlaySources 的 isMp4 正则校验通过
		// （后端 :id 路由会剥离该后缀）；认证通过 query tempToken 完成（见 download_handler.File）。
		playURL := fmt.Sprintf("第1集$/api/download/file/%d.mp4#", taskID)

		video := entity.LocalVideo{
			VodID:          vodID,
			VodName:        entry.Title,
			VodSub:         "",
			VodClass:       entry.Category,
			VodPic:         entry.CoverPath,
			VodActor:       "暂无",
			VodDirector:    "暂无",
			VodBlurb:       "暂无",
			VodContent:     "暂无",
			VodRemarks:     "本地资源",
			VodArea:        "暂无",
			VodLang:        "暂无",
			VodYear:        "",
			VodScore:       "",
			VodPlayFrom:    "local",
			VodPlayURL:     playURL,
			TypeName:       entry.Category,
			FilePath:       entry.FilePath,
			DownloadTaskID: taskID,
		}
		videos = append(videos, video)

		slog.Info("demo video indexed",
			"vod_id", vodID,
			"title", entry.Title,
			"category", entry.Category,
			"cover", entry.CoverPath,
			"task_id", taskID,
		)
	}

	// 4. 批量写入 local_video 表
	if err := s.localVideoRepo.BatchCreate(videos); err != nil {
		return fmt.Errorf("batch create local_video failed: %w", err)
	}

	// 5. 写入虚拟资源站点配置
	if err := s.ensureDemoSiteConfig(ctx); err != nil {
		return fmt.Errorf("ensure demo site config failed: %w", err)
	}

	slog.Info("demo data scan completed",
		"total_videos", len(videos),
		"dir", absDir,
	)

	return nil
}

// videoEntry 扫描得到的单个视频条目
type videoEntry struct {
	Title     string // 视频标题（文件名去扩展名）
	Category  string // 分类（父文件夹名）
	FilePath  string // 视频文件绝对路径
	CoverPath string // 封面图片路径（可为空）
}

// scanDirectory 递归扫描目录，返回视频条目列表
// 目录结构约定：文件夹作为分类（type_name / vod_class），文件夹内的视频文件作为条目
// 支持两种结构：
//   - 根目录下直接放视频文件（category="默认分类"）
//   - 根目录下按文件夹分类，文件夹内放视频文件
func (s *LocalDataService) scanDirectory(rootDir string) []videoEntry {
	var entries []videoEntry

	err := filepath.Walk(rootDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			slog.Warn("walk error", "path", path, "error", err)
			return nil // 跳过错误继续
		}

		// 跳过目录本身
		if info.IsDir() {
			return nil
		}

		// 只处理视频文件
		ext := strings.ToLower(filepath.Ext(path))
		if !videoExts[ext] {
			return nil
		}

		absPath, _ := filepath.Abs(path)

		// 分类：取相对于 rootDir 的第一级目录名，若直接在根目录则用"默认分类"
		relPath, err := filepath.Rel(rootDir, absPath)
		if err != nil {
			relPath = filepath.Base(absPath)
		}
		parts := strings.Split(filepath.ToSlash(relPath), "/")
		category := "默认分类"
		if len(parts) > 1 {
			category = parts[0]
		}

		// 标题：文件名去扩展名
		title := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))

		// 封面关联：同名前缀图片优先，否则取同目录任意图片
		cover := s.findCover(absPath)

		entries = append(entries, videoEntry{
			Title:     title,
			Category:  category,
			FilePath:  absPath,
			CoverPath: cover,
		})

		return nil
	})

	if err != nil {
		slog.Error("scan directory failed", "dir", rootDir, "error", err)
	}

	return entries
}

// findCover 查找视频文件对应的封面图片
// 规则：1. 同名前缀图片优先（movie.mp4 -> movie.jpg）
//
//  2. 否则取同目录内任意第一张图片
func (s *LocalDataService) findCover(videoPath string) string {
	dir := filepath.Dir(videoPath)
	videoName := strings.TrimSuffix(filepath.Base(videoPath), filepath.Ext(videoPath))

	// 1. 查找同名前缀图片
	for ext := range imageExts {
		candidate := filepath.Join(dir, videoName+ext)
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}

	// 2. 查找同目录内任意图片
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		ext := strings.ToLower(filepath.Ext(entry.Name()))
		if imageExts[ext] {
			return filepath.Join(dir, entry.Name())
		}
	}

	// 3. 未找到封面图片，使用 ffmpeg 截取视频第一帧作为默认封面
	coverPath := filepath.Join(dir, videoName+".jpg")
	if extracted, err := extractFirstFrame(videoPath, coverPath); err != nil {
		slog.Warn("failed to extract first frame as cover, falling back to empty",
			"video", videoPath, "error", err)
		return ""
	} else if extracted {
		slog.Info("extracted first frame as default cover", "video", videoPath, "cover", coverPath)
		return coverPath
	}

	return ""
}

// extractFirstFrame 使用 ffmpeg 截取视频第一帧并保存为 JPG 图片。
// 成功返回 (true, nil)；ffmpeg 不可用或截取失败返回 (false, error)。
// 截取的图片按原始分辨率输出，单帧、快速。
func extractFirstFrame(videoPath, outputPath string) (bool, error) {
	// 检查 ffmpeg 是否可用
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		return false, fmt.Errorf("ffmpeg not found: %w", err)
	}

	// 如果目标图片已存在，先删除避免复用旧文件
	_ = os.Remove(outputPath)

	// ffmpeg -i input -frames:v 1 -q:v 2 -y output.jpg
	//   -frames:v 1     只取第 1 帧
	//   -q:v 2          JPEG 质量（2~31，越小质量越高，2 为高质量）
	//   -y              覆盖输出
	cmd := exec.Command("ffmpeg",
		"-y",
		"-i", videoPath,
		"-frames:v", "1",
		"-q:v", "2",
		outputPath,
	)

	// 设置超时（截取单帧通常很快，30s 足够）
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	cmd = exec.CommandContext(ctx, cmd.Args[0], cmd.Args[1:]...)

	output, err := cmd.CombinedOutput()
	if err != nil {
		_ = os.Remove(outputPath)
		return false, fmt.Errorf("ffmpeg extract first frame failed: %w, output: %s", err, string(output))
	}

	// 验证输出文件存在且非空
	info, err := os.Stat(outputPath)
	if err != nil {
		return false, fmt.Errorf("cover file not found after extraction: %w", err)
	}
	if info.Size() == 0 {
		_ = os.Remove(outputPath)
		return false, fmt.Errorf("extracted cover file is empty")
	}

	return true, nil
}

// createDemoTask 为本地视频创建 download_task 记录（status=Completed）
// vodID 对应 local_video 表的 vod_id，用于 checkDownload 按 vod_id 匹配
func (s *LocalDataService) createDemoTask(entry videoEntry, vodID int64) (int64, error) {
	// 获取文件大小
	var fileSize int64
	if info, err := os.Stat(entry.FilePath); err == nil {
		fileSize = info.Size()
	}

	task := &entity.DownloadTask{
		UserID:         DemoUserID,
		VodID:          vodID,
		VodName:        entry.Title,
		VodPic:         entry.CoverPath,
		ResourceDomain: DemoDomain,
		ResourceName:   "本地演示资源",
		GroupKey:       "",
		SourceIndex:    0,
		EpIndex:        0,
		EpName:         "第1集",
		M3u8URL:        "local://" + entry.FilePath, // 占位，标记为本地资源
		Status:         entity.DownloadStatusCompleted,
		Progress:       100.0,
		TotalSegments:  0,
		FilePath:       entry.FilePath,
		FileSize:       fileSize,
	}

	created, err := s.downloadRepo.Create(task)
	if err != nil {
		return 0, err
	}
	return created.ID, nil
}

// clearOldDemoTasks 清理旧的 demo download_task 记录
func (s *LocalDataService) clearOldDemoTasks() error {
	// 物理删除 resource_domain=local_demo_domain 的所有记录
	return s.downloadRepo.DeleteByDomain(DemoDomain)
}

// ensureDemoSiteConfig 确保虚拟资源站点配置存在于 sys_config 表
func (s *LocalDataService) ensureDemoSiteConfig(ctx context.Context) error {
	// 检查是否已存在
	existing, err := s.sysConfigRepo.GetByKey(ctx, DemoDomain)
	if err == nil && existing != nil {
		return nil // 已存在，不重复创建
	}

	// 创建虚拟站点配置
	// 字段含义参考 ResourceService 的 siteItem 映射：
	//   ConfigKey = domain
	//   Title = 站点名称
	//   Value1 = API URL（占位）
	//   Value2 = Detail URL（占位）
	//   Value3 = Comment
	//   Value4 = CacheTime
	//   Value5 = IsAdult ("0" = 非NSFW)
	//   Value6 = Searchable ("1" = 允许搜索)
	site := &entity.SysConfig{
		ConfigKey:   DemoDomain,
		ConfigGroup: "resource_site",
		Title:       "本地演示资源",
		Value1:      "local://demo",
		Value2:      "local://demo",
		Value3:      "Apple Store 审核演示本地数据",
		Value4:      "0",
		Value5:      "0",
		Value6:      "1",
		SortOrder:   999,
		IsEnabled:   true,
		Remark:      "本地演示虚拟站点，数据来自 MEOWTV_DEMO_DATA_DIR 扫描",
	}

	return s.sysConfigRepo.Create(ctx, site)
}
