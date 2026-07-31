package handler

import (
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// DownloadHandler 下载模块接口
type DownloadHandler struct {
	downloadService *service.DownloadService
}

// NewDownloadHandler 创建下载模块 Handler
func NewDownloadHandler(downloadService *service.DownloadService) *DownloadHandler {
	return &DownloadHandler{downloadService: downloadService}
}

// Create 创建下载任务
func (h *DownloadHandler) Create(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.DownloadCreateReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	// 转换为 Service 层请求
	items := make([]service.CreateTaskItem, len(req.Items))
	for i, item := range req.Items {
		items[i] = service.CreateTaskItem{
			SourceIndex: item.SourceIndex,
			EpIndex:     item.EpIndex,
			EpName:      item.EpName,
			M3u8URL:     item.M3u8URL,
		}
	}

	result, err := h.downloadService.CreateTasks(userID, service.CreateTasksRequest{
		VodID:          req.VodID,
		VodName:        req.VodName,
		VodPic:         req.VodPic,
		ResourceDomain: req.ResourceDomain,
		ResourceName:   req.ResourceName,
		GroupKey:       req.GroupKey,
		Items:          items,
	})
	if err != nil {
		return err
	}

	return response.OK(c, response.DownloadCreateResp{
		TaskIDs: result.TaskIDs,
		Queued:  result.Queued,
		Skipped: result.Skipped,
		Retried: result.Retried,
		Messages: func() []response.DownloadCreateMsg {
			msgs := make([]response.DownloadCreateMsg, len(result.Messages))
			for i, m := range result.Messages {
				msgs[i] = response.DownloadCreateMsg{
					EpIndex: m.EpIndex,
					EpName:  m.EpName,
					Type:    m.Type,
					Message: m.Message,
				}
			}
			return msgs
		}(),
	})
}

// List 获取下载任务列表
func (h *DownloadHandler) List(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.DownloadListReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if req.Limit == 0 {
		req.Limit = 20
	}

	tasks, total, err := h.downloadService.ListTasks(userID, req.Status, req.Limit, req.Offset)
	if err != nil {
		return err
	}

	items := make([]response.DownloadTaskItem, len(tasks))
	for i, t := range tasks {
		items[i] = response.NewDownloadTaskItem(&t)
	}

	return response.OK(c, response.DownloadListResp{
		Total: total,
		Items: items,
	})
}

// Cancel 取消下载任务
func (h *DownloadHandler) Cancel(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.DownloadTaskIDReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if err := h.downloadService.CancelTask(userID, req.TaskID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// Delete 删除下载任务
func (h *DownloadHandler) Delete(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.DownloadTaskIDReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if err := h.downloadService.DeleteTask(userID, req.TaskID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// Retry 重试下载任务
func (h *DownloadHandler) Retry(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.DownloadTaskIDReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if err := h.downloadService.RetryTask(userID, req.TaskID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// Check 检查是否有本地下载文件
// 不限定用户：只要该资源有已完成下载即可播放（本地优先播放检查）
func (h *DownloadHandler) Check(c echo.Context) error {
	var req request.DownloadCheckReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	found, taskID, fileURL, fileFormat := h.downloadService.CheckDownload(req.ResourceDomain, req.VodID, req.SourceIndex, req.EpIndex)
	return response.OK(c, response.DownloadCheckResp{
		Found:      found,
		TaskID:     taskID,
		FileURL:    fileURL,
		FileFormat: fileFormat,
	})
}

// File 流式播放已下载的文件（支持 Range 请求）
// 认证方式：临时 Token（query param token，由 TempTokenAuth 中间件验证）。
// Artplayer 通过 video.src 加载，无法设置 Authorization header，因此改用临时 Token。
// 路由 :id 可能带 .mp4 伪扩展（用于绕过前端 parsePlaySources 的格式过滤），此处剥离。
// 临时 Token 模式下不绑定具体 userID，因此跳过 task 归属校验（token 已证明登录身份）。
func (h *DownloadHandler) File(c echo.Context) error {
	// TempTokenAuth 中间件验证通过后不设置 UserIDKey，这里无需读取
	taskIDStr := c.Param("id")
	// 剥离可能的 .mp4 伪扩展后缀
	if idx := strings.LastIndex(taskIDStr, "."); idx > 0 {
		taskIDStr = taskIDStr[:idx]
	}
	taskID, err := strconv.ParseInt(taskIDStr, 10, 64)
	if err != nil {
		return echo.NewHTTPError(http.StatusBadRequest, "无效的任务 ID")
	}

	// 临时 Token 模式下跳过用户归属校验（token 已认证，taskID 难以枚举）
	filePath, err := h.downloadService.GetTaskFilePathSkipUserCheck(taskID)
	if err != nil {
		return echo.NewHTTPError(http.StatusNotFound, err.Error())
	}

	f, err := os.Open(filePath)
	if err != nil {
		return echo.NewHTTPError(http.StatusNotFound, "文件不存在")
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil || info.IsDir() {
		return echo.NewHTTPError(http.StatusNotFound, "文件不存在")
	}

	// 记录请求信息，便于排查 Range/seek 问题
	slog.Info("download file serve",
		"task_id", taskID,
		"file", filepath.Base(filePath),
		"method", c.Request().Method,
		"range", c.Request().Header.Get("Range"),
		"if_range", c.Request().Header.Get("If-Range"),
	)

	http.ServeContent(c.Response(), c.Request(), info.Name(), info.ModTime(), f)
	return nil
}

// ── 管理端接口 ──────────────────────────────────────────────────────────────

// AdminList 管理端查看所有下载任务
func (h *DownloadHandler) AdminList(c echo.Context) error {
	var req request.DownloadListReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if req.Limit == 0 {
		req.Limit = 20
	}

	tasks, total, err := h.downloadService.ListAllTasks(req.Status, req.Limit, req.Offset)
	if err != nil {
		return err
	}

	items := make([]response.DownloadTaskItem, len(tasks))
	for i, t := range tasks {
		items[i] = response.NewDownloadTaskItem(&t)
	}

	return response.OK(c, response.DownloadListResp{
		Total: total,
		Items: items,
	})
}

// AdminGetConfig 管理端获取下载配置
func (h *DownloadHandler) AdminGetConfig(c echo.Context) error {
	cfg := h.downloadService.GetConfig()
	return response.OK(c, response.DownloadConfigResp{
		DownloadDir:        cfg.DownloadDir,
		MaxConcurrent:      cfg.MaxConcurrent,
		SegmentConcurrency: cfg.SegmentConcurrency,
	})
}

// AdminUpdateConfig 管理端更新下载配置
func (h *DownloadHandler) AdminUpdateConfig(c echo.Context) error {
	var req request.DownloadConfigUpdateReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	h.downloadService.UpdateConfig(req.DownloadDir, req.MaxConcurrent, req.SegmentConcurrency)
	return response.OK(c, nil)
}
