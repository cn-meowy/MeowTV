package service

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

const (
	configKeyDownload         = "download_config"
	downloadDirDefault        = "data/downloads"
	maxConcurrentDefault      = 2
	segmentConcurrencyDefault = 10
)

// DownloadService 下载业务层
type DownloadService struct {
	repo            *repository.DownloadRepository
	configService   *SysConfigService
	parser          *M3u8Parser
	cache           cache.Cache
	taskQueue       chan int64
	activeCount     atomic.Int32
	cancelFuncs     sync.Map
	mu              sync.RWMutex
	httpClient      *http.Client
	stopCh          chan struct{}
	wg              sync.WaitGroup
	ffmpegAvailable bool
	ffmpegVersion   string
}

// NewDownloadService 创建下载 Service
func NewDownloadService(repo *repository.DownloadRepository, configService *SysConfigService, cacheProvider cache.Cache) *DownloadService {
	s := &DownloadService{
		repo: repo, configService: configService, cache: cacheProvider,
		taskQueue:  make(chan int64, 100),
		httpClient: &http.Client{Timeout: 60 * time.Second},
		stopCh:     make(chan struct{}),
	}
	s.parser = NewM3u8Parser(s.httpClient)
	return s
}

// Start 启动 Worker Pool，ffmpeg 不可用时返回错误阻止启动
func (s *DownloadService) Start() error {
	// 检测 ffmpeg
	available, path, version := CheckFFmpeg()
	s.ffmpegAvailable = available
	s.ffmpegVersion = version

	if !available {
		slog.Error("ffmpeg not found! Download service requires ffmpeg to convert TS to MP4.",
			"install_macOS", "brew install ffmpeg",
			"install_Linux", "apt install ffmpeg / yum install ffmpeg",
		)
		return fmt.Errorf("ffmpeg not found in PATH, download service cannot start without ffmpeg")
	}

	slog.Info("ffmpeg detected", "path", path, "version", version)

	mc := s.getMaxConcurrent()
	slog.Info("download service starting", "max_concurrent", mc)
	for i := 0; i < mc; i++ {
		s.wg.Add(1)
		go s.worker()
	}
	go s.recoverPendingTasks()
	return nil
}

// Stop 停止 Worker Pool
func (s *DownloadService) Stop() {
	slog.Info("download service stopping...")
	close(s.stopCh)
	s.cancelFuncs.Range(func(key, value interface{}) bool {
		if cancel, ok := value.(context.CancelFunc); ok {
			cancel()
		}
		return true
	})
	s.wg.Wait()
	slog.Info("download service stopped")
}

// CreateTasks 批量创建下载任务
func (s *DownloadService) CreateTasks(userID int64, req CreateTasksRequest) (*CreateTasksResult, error) {
	result := &CreateTasksResult{}
	for _, item := range req.Items {
		existing, err := s.repo.FindByUserAndURL(userID, item.M3u8URL)
		if err != nil || existing == nil {
			// 未找到 → 按未下载逻辑处理，创建新任务
			task := &entity.DownloadTask{
				UserID: userID, VodID: req.VodID, VodName: req.VodName, VodPic: req.VodPic,
				ResourceDomain: req.ResourceDomain, ResourceName: req.ResourceName, GroupKey: req.GroupKey,
				SourceIndex: item.SourceIndex, EpIndex: item.EpIndex, EpName: item.EpName,
				M3u8URL: item.M3u8URL, Status: entity.DownloadStatusQueued,
			}
			created, err := s.repo.Create(task)
			if err != nil {
				slog.Error("create download task failed", "error", err)
				continue
			}
			result.TaskIDs = append(result.TaskIDs, created.ID)
			result.Queued++
			s.taskQueue <- created.ID
			continue
		}

		// 找到已有任务，根据状态分支处理
		switch {
		case existing.Status == entity.DownloadStatusCompleted:
			// 已完成 → 提示请勿重复添加
			result.Skipped++
			result.Messages = append(result.Messages, CreateTaskMessage{
				EpIndex: item.EpIndex,
				EpName:  item.EpName,
				Type:    "completed",
				Message: "任务已完成，请勿重复添加",
			})

		case existing.Status == entity.DownloadStatusFailed,
			existing.Status == entity.DownloadStatusCancelled:
			// 已失败/已取消 → 重新开始下载
			tmpDir := filepath.Join(s.getDownloadDir(), "tmp", strconv.FormatInt(existing.ID, 10))
			_ = os.RemoveAll(tmpDir)
			_ = s.repo.ResetForRetry(existing.ID)
			s.taskQueue <- existing.ID
			result.Retried++
			result.TaskIDs = append(result.TaskIDs, existing.ID)
			result.Messages = append(result.Messages, CreateTaskMessage{
				EpIndex: item.EpIndex,
				EpName:  item.EpName,
				Type:    "retried",
				Message: "任务已存在，正在重新下载",
			})

		default:
			// 活跃状态（排队/解析/下载/合并）→ 提示正在下载
			result.Skipped++
			result.Messages = append(result.Messages, CreateTaskMessage{
				EpIndex: item.EpIndex,
				EpName:  item.EpName,
				Type:    "active",
				Message: "任务已存在，正在重新下载",
			})
		}
	}
	return result, nil
}

// ListTasks 查询用户下载任务列表
func (s *DownloadService) ListTasks(userID int64, status *int, limit, offset int) ([]entity.DownloadTask, int64, error) {
	tasks, err := s.repo.List(userID, status, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	total, err := s.repo.Count(userID, status)
	return tasks, total, err
}

// CancelTask 取消下载任务
func (s *DownloadService) CancelTask(userID, taskID int64) error {
	task, err := s.repo.GetByID(taskID)
	if err != nil {
		return err
	}
	if task.UserID != userID {
		return errs.New(http.StatusForbidden, "无权操作此任务")
	}
	if task.Status.IsTerminal() {
		return errs.New(http.StatusBadRequest, "任务已结束，无法取消")
	}
	if cancel, ok := s.cancelFuncs.Load(taskID); ok {
		cancel.(context.CancelFunc)()
	}
	return s.repo.UpdateStatus(taskID, entity.DownloadStatusCancelled, "")
}

// DeleteTask 删除下载任务及文件
func (s *DownloadService) DeleteTask(userID, taskID int64) error {
	task, err := s.repo.GetByID(taskID)
	if err != nil {
		return err
	}
	if task.UserID != userID {
		return errs.New(http.StatusForbidden, "无权操作此任务")
	}
	if !task.Status.IsTerminal() {
		if cancel, ok := s.cancelFuncs.Load(taskID); ok {
			cancel.(context.CancelFunc)()
		}
	}
	if task.FilePath != "" {
		_ = os.Remove(task.FilePath)
	}
	tmpDir := filepath.Join(s.getDownloadDir(), "tmp", strconv.FormatInt(taskID, 10))
	_ = os.RemoveAll(tmpDir)
	return s.repo.Delete(taskID)
}

// RetryTask 重试失败任务
func (s *DownloadService) RetryTask(userID, taskID int64) error {
	task, err := s.repo.GetByID(taskID)
	if err != nil {
		return err
	}
	if task.UserID != userID {
		return errs.New(http.StatusForbidden, "无权操作此任务")
	}
	if task.Status != entity.DownloadStatusFailed && task.Status != entity.DownloadStatusCancelled {
		return errs.New(http.StatusBadRequest, "只能重试失败或已取消的任务")
	}
	tmpDir := filepath.Join(s.getDownloadDir(), "tmp", strconv.FormatInt(taskID, 10))
	_ = os.RemoveAll(tmpDir)
	_ = s.repo.UpdateStatus(taskID, entity.DownloadStatusQueued, "")
	s.taskQueue <- taskID
	return nil
}

// CheckDownload 检查是否有本地下载文件，返回 (found, taskID, fileURL, fileFormat)
// 不限定用户：只要该资源有已完成下载即可播放（本地优先播放检查）
func (s *DownloadService) CheckDownload(resourceDomain string, vodID int64, sourceIndex, epIndex int) (bool, int64, string, string) {
	task, err := s.repo.FindCompleted(resourceDomain, vodID, sourceIndex, epIndex)
	if err != nil {
		return false, 0, "", ""
	}
	fileFormat := "ts"
	if strings.HasSuffix(strings.ToLower(task.FilePath), ".mp4") {
		fileFormat = "mp4"
	}
	return true, task.ID, fmt.Sprintf("/api/download/file/%d", task.ID), fileFormat
}

// SaveFromStream 从流缓存保存为下载任务（实现 SaveCallback 接口）
func (s *DownloadService) SaveFromStream(sessionKey string, segmentDir string, totalSegments int,
	userID int64, vodInfo *VodInfo, m3u8Info *M3u8Info) (int64, error) {

	slog.Info("SaveFromStream starting",
		"session_key", sessionKey,
		"segment_dir", segmentDir,
		"total_segments", totalSegments,
		"user_id", userID,
		"vod_id", vodInfo.VodID,
		"vod_name", vodInfo.VodName,
		"ep_name", vodInfo.EpName)

	// 1. 创建 DownloadTask 记录（补全所有资源信息）
	task := &entity.DownloadTask{
		UserID:         userID,
		VodID:          vodInfo.VodID,
		VodName:        vodInfo.VodName,
		VodPic:         vodInfo.VodPic,
		ResourceDomain: vodInfo.ResourceDomain,
		ResourceName:   vodInfo.ResourceName,
		GroupKey:       vodInfo.GroupKey,
		SourceIndex:    vodInfo.SourceIndex,
		EpIndex:        vodInfo.EpIndex,
		EpName:         vodInfo.EpName,
		M3u8URL:        vodInfo.M3u8URL,
		Status:         entity.DownloadStatusMerging,
		TotalSegments:  totalSegments,
	}
	created, err := s.repo.Create(task)
	if err != nil {
		return 0, fmt.Errorf("create download task: %w", err)
	}
	taskID := created.ID

	// 2. 创建输出目录
	outputDir := filepath.Join(s.getDownloadDir(), sanitizeFilename(vodInfo.VodName))
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		s.failTask(taskID, fmt.Sprintf("创建输出目录失败: %v", err))
		return 0, err
	}

	// 3. 流式拼接 TS 文件
	tsPath := filepath.Join(outputDir, sanitizeFilename(vodInfo.EpName)+".ts")
	mp4Path := filepath.Join(outputDir, sanitizeFilename(vodInfo.EpName)+".mp4")

	// 防御性检查：即使 Start() 时通过，运行期间 ffmpeg 也可能被卸载
	if !s.ffmpegAvailable {
		s.failTask(taskID, "ffmpeg 不可用，无法将 TS 转封装为 MP4")
		return 0, fmt.Errorf("ffmpeg not available")
	}

	// 流式拼接 TS（如果分片加密，合并时先解密）
	slog.Info("SaveFromStream: stream concat ts", "task_id", taskID, "segments", totalSegments)
	if err := streamConcatTS(segmentDir, totalSegments, tsPath, m3u8Info); err != nil {
		s.failTask(taskID, fmt.Sprintf("流式拼接 TS 文件失败: %v", err))
		return 0, err
	}

	var outputPath string
	var fileSize int64

	// 4. 尝试 remux 为 MP4
	if result, remuxErr := remuxToMP4(tsPath, mp4Path); remuxErr == nil {
		_ = os.Remove(tsPath)
		outputPath = result
		if fi, statErr := os.Stat(outputPath); statErr == nil {
			fileSize = fi.Size()
		}
		slog.Info("SaveFromStream: remux to mp4 success",
			"task_id", taskID, "file", outputPath, "size_mb", fileSize/1024/1024)
	} else {
		// 备选：保留 TS 文件
		slog.Warn("SaveFromStream: remux failed, keeping ts",
			"task_id", taskID, "error", remuxErr)
		outputPath = tsPath
		if fi, statErr := os.Stat(tsPath); statErr == nil {
			fileSize = fi.Size()
		}
	}

	// 5. 标记完成
	_ = s.repo.UpdateCompleted(taskID, outputPath, fileSize)
	slog.Info("SaveFromStream completed",
		"task_id", taskID,
		"file", outputPath,
		"size_mb", fileSize/1024/1024)

	return taskID, nil
}

// GetTaskFilePath 获取任务文件路径（用于流式播放，JWT 认证模式）
// 如果文件是 TS 格式，尝试即时 remux 为 MP4（对遗留 TS 文件自动转封装并缓存）
func (s *DownloadService) GetTaskFilePath(userID, taskID int64) (string, error) {
	task, err := s.repo.GetByID(taskID)
	if err != nil {
		return "", err
	}
	// Demo 模式：本地演示数据（UserID=0 且 ResourceDomain=local_demo_domain）跳过用户归属校验
	if task.UserID != userID && !(task.UserID == DemoUserID && task.ResourceDomain == DemoDomain) {
		return "", errs.New(http.StatusForbidden, "无权访问此文件")
	}
	return s.resolveFilePath(task)
}

// GetTaskFilePathSkipUserCheck 获取任务文件路径，跳过用户归属校验
// 用于临时 Token 认证模式（/api/download/file/:id）：
// 临时 Token 已由 TempTokenAuth 中间件验证登录身份，无需再校验 task.UserID。
// taskID 为自增整数，难以枚举，且文件名信息有限，风险可控。
func (s *DownloadService) GetTaskFilePathSkipUserCheck(taskID int64) (string, error) {
	task, err := s.repo.GetByID(taskID)
	if err != nil {
		return "", err
	}
	return s.resolveFilePath(task)
}

// resolveFilePath 处理文件状态校验与 TS->MP4 即时 remux 的共享逻辑
func (s *DownloadService) resolveFilePath(task *entity.DownloadTask) (string, error) {
	if task.Status != entity.DownloadStatusCompleted {
		return "", errs.New(http.StatusBadRequest, "文件尚未下载完成")
	}
	if task.FilePath == "" {
		return "", errs.New(http.StatusBadRequest, "文件路径为空")
	}

	taskID := task.ID
	// 即时 remux：如果文件是 TS 格式，尝试转封装为 MP4
	if strings.HasSuffix(strings.ToLower(task.FilePath), ".ts") {
		mp4Path := task.FilePath[:len(task.FilePath)-3] + ".mp4"

		// 检查是否已有缓存的 MP4 文件
		if _, statErr := os.Stat(mp4Path); statErr == nil {
			slog.Info("found cached mp4, updating db path", "task_id", taskID, "mp4", mp4Path)
			_ = s.repo.UpdateFilePath(taskID, mp4Path)
			return mp4Path, nil
		}

		// 尝试即时 remux
		if result, remuxErr := remuxToMP4(task.FilePath, mp4Path); remuxErr == nil {
			// remux 成功，删除旧 TS 文件，更新 DB
			_ = os.Remove(task.FilePath)
			_ = s.repo.UpdateFilePath(taskID, result)
			slog.Info("on-the-fly remux success", "task_id", taskID, "mp4", result)
			return result, nil
		} else {
			// remux 失败（ffmpeg 不可用等），fallback 继续使用 TS
			slog.Warn("on-the-fly remux failed, serving TS file", "task_id", taskID, "error", remuxErr)
		}
	}

	return task.FilePath, nil
}

// ListAllTasks 管理端查看所有用户任务
func (s *DownloadService) ListAllTasks(status *int, limit, offset int) ([]entity.DownloadTask, int64, error) {
	tasks, err := s.repo.ListAll(status, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	total, err := s.repo.CountAll(status)
	return tasks, total, err
}

// GetConfig 获取下载配置
func (s *DownloadService) GetConfig() *response.DownloadConfigResp {
	return &response.DownloadConfigResp{
		DownloadDir:        s.getDownloadDir(),
		MaxConcurrent:      s.getMaxConcurrent(),
		SegmentConcurrency: s.getSegmentConcurrency(),
		FfmpegAvailable:    s.ffmpegAvailable,
		FfmpegVersion:      s.ffmpegVersion,
	}
}

// UpdateConfig 更新下载配置
func (s *DownloadService) UpdateConfig(dir string, maxConcurrent, segConcurrency int) {
	ctx := context.Background()
	cfg := s.configService.GetValue(ctx, configKeyDownload)
	if cfg == nil {
		// 创建新配置
		_ = s.configService.Create(ctx, &request.ConfigCreateReq{
			ConfigKey:   configKeyDownload,
			ConfigGroup: "system",
			Title:       "下载配置",
			Title1:      "下载目录",
			Title2:      "最大并发下载数",
			Title3:      "分片并发数",
			Value1:      dir,
			Value2:      strconv.Itoa(maxConcurrent),
			Value3:      strconv.Itoa(segConcurrency),
			IsEnabled:   true,
		})
	} else {
		// 更新已有配置
		v1 := dir
		v2 := strconv.Itoa(maxConcurrent)
		v3 := strconv.Itoa(segConcurrency)
		_ = s.configService.Update(ctx, &request.ConfigUpdateReq{
			ConfigKey: configKeyDownload,
			Value1:    &v1,
			Value2:    &v2,
			Value3:    &v3,
		})
	}
}

// DownloadConfigResp 下载配置响应
type DownloadConfigResp struct {
	DownloadDir        string
	MaxConcurrent      int
	SegmentConcurrency int
}

// CreateTasksRequest 创建任务请求
type CreateTasksRequest struct {
	VodID          int64
	VodName        string
	VodPic         string
	ResourceDomain string
	ResourceName   string
	GroupKey       string
	Items          []CreateTaskItem
}

// CreateTaskItem 创建任务项
type CreateTaskItem struct {
	SourceIndex int
	EpIndex     int
	EpName      string
	M3u8URL     string
}

// CreateTaskMessage 单个任务的处理提示消息
type CreateTaskMessage struct {
	EpIndex int    `json:"ep_index"`
	EpName  string `json:"ep_name"`
	Type    string `json:"type"` // "completed" | "retried" | "active"
	Message string `json:"message"`
}

// CreateTasksResult 创建任务结果
type CreateTasksResult struct {
	TaskIDs  []int64             `json:"task_ids"`
	Queued   int                 `json:"queued"`
	Skipped  int                 `json:"skipped"`
	Retried  int                 `json:"retried"`  // 重新下载的任务数
	Messages []CreateTaskMessage `json:"messages"` // 每个任务的处理提示
}
