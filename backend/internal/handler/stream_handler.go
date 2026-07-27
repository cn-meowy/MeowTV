package handler

import (
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

const (
	// proxyTimeout 透传请求超时
	proxyTimeout = 60 * time.Second
)

// StreamHandler 流代理模块接口
type StreamHandler struct {
	streamService *service.StreamService
}

// NewStreamHandler 创建流代理 Handler
func NewStreamHandler(streamService *service.StreamService) *StreamHandler {
	return &StreamHandler{streamService: streamService}
}

// ProxyM3U8 代理 m3u8，返回重写后的内容
// GET /api/stream/proxy/m3u8?url=<encoded_url>&token=<temp_token>
// token 参数为临时 token（由 TempTokenAuth 中间件验证）
// 当 token 参数存在时，m3u8 中的 TS/Key URL 会包含 token，AVPlayer 子请求自动携带
func (h *StreamHandler) ProxyM3U8(c echo.Context) error {
	urlStr := c.QueryParam("url")
	if urlStr == "" {
		return response.Fail(c, errs.New(http.StatusBadRequest, "url is required"))
	}

	// 从中间件获取已验证的临时 token
	token := middleware.GetTempToken(c)

	m3u8Content, sessionKey, err := h.streamService.ProxyM3U8(urlStr, token)
	if err != nil {
		slog.Error("proxy m3u8 failed", "url", urlStr, "error", err)
		return response.Fail(c, errs.New(http.StatusBadGateway, "failed to proxy m3u8: "+err.Error()))
	}

	// 自动将当前用户添加到 Session，让调度器可以开始调度分片下载
	// 打破"没有用户就不调度"的死锁
	userID := middleware.GetUserID(c)
	if userID > 0 && sessionKey != "" {
		_, _ = h.streamService.AddUser(sessionKey, userID)
	}

	// 设置响应头
	c.Response().Header().Set("Content-Type", "application/vnd.apple.mpegurl")
	c.Response().Header().Set("Cache-Control", "no-cache, no-store")

	return c.Blob(http.StatusOK, "application/vnd.apple.mpegurl", m3u8Content)
}

// ProxyKey 代理 AES-128 解密 key
// GET /api/stream/proxy/key?session=<key>&keyuri=<encoded_keyuri>
func (h *StreamHandler) ProxyKey(c echo.Context) error {
	sessionKey := c.QueryParam("session")
	keyURI := c.QueryParam("keyuri")

	if sessionKey == "" || keyURI == "" {
		return response.Fail(c, errs.New(http.StatusBadRequest, "session and keyuri are required"))
	}

	keyData, err := h.streamService.ProxyKey(sessionKey, keyURI)
	if err != nil {
		slog.Warn("proxy key failed", "session", sessionKey, "keyuri", keyURI, "error", err)
		return response.Fail(c, errs.New(http.StatusNotFound, "encryption key not found"))
	}

	c.Response().Header().Set("Content-Type", "application/octet-stream")
	c.Response().Header().Set("Cache-Control", "no-cache")
	c.Response().Header().Set("Content-Length", strconv.Itoa(len(keyData)))

	return c.Blob(http.StatusOK, "application/octet-stream", keyData)
}

// ProxyTS 代理 TS 分片
// 已缓存分片：直接返回缓存数据，支持 Range 请求（206 Partial Content）
// 未缓存分片：反向代理透传到原始视频源 URL，同时通知调度器后台下载
// GET /api/stream/proxy/ts?session=<key>&index=<N>
func (h *StreamHandler) ProxyTS(c echo.Context) error {
	sessionKey := c.QueryParam("session")
	indexStr := c.QueryParam("index")

	if sessionKey == "" || indexStr == "" {
		return response.Fail(c, errs.New(http.StatusBadRequest, "session and index are required"))
	}

	segmentIndex, err := strconv.Atoi(indexStr)
	if err != nil {
		return response.Fail(c, errs.New(http.StatusBadRequest, "invalid index"))
	}

	// 获取 session
	session, ok := h.streamService.GetSession(sessionKey)
	if !ok {
		slog.Warn("session not found", "session", sessionKey)
		return response.Fail(c, errs.New(http.StatusNotFound, "session not found"))
	}

	// 记录播放器实际请求的分片索引，用于即时 seek 检测
	// 相比依赖前端周期性进度上报，通过播放器实际请求行为能更早检测到 seek
	// RecordSegmentRequest 内部会在检测到 seek 时通知调度器重排任务队列
	userID := middleware.GetUserID(c)
	if userID > 0 {
		h.streamService.RecordSegmentRequest(sessionKey, userID, segmentIndex)
	}

	cacheManager := session.GetCacheManager()

	// 如果分片还在 Pending/Failed 状态，主动通知调度器优先下载该分片
	// 后台 Worker 继续下载缓存，后续请求可命中缓存
	if status := cacheManager.GetStatus(segmentIndex); status == service.SegmentStatusPending || status == service.SegmentStatusFailed {
		h.streamService.NotifyUrgentSegment(sessionKey, segmentIndex)
	}

	// 分片已缓存：返回缓存数据，支持 Range 请求
	if cacheManager.GetStatus(segmentIndex) == service.SegmentStatusDone {
		data, err := cacheManager.GetSegmentData(segmentIndex)
		if err != nil {
			if err == service.ErrSegmentExpired {
				return response.Fail(c, errs.New(http.StatusGone, "segment file expired"))
			}
			return response.Fail(c, errs.New(http.StatusInternalServerError, "failed to get segment data"))
		}

		return h.serveSegmentWithRange(c, data)
	}

	// 分片未缓存：反向代理透传到原始视频源 URL
	return h.proxySegmentFromOrigin(c, session, segmentIndex)
}

// serveSegmentWithRange 返回分片数据，支持 Range 请求（206 Partial Content）
func (h *StreamHandler) serveSegmentWithRange(c echo.Context, data []byte) error {
	c.Response().Header().Set("Content-Type", "video/mp2t")
	c.Response().Header().Set("Cache-Control", "no-cache")
	c.Response().Header().Set("Accept-Ranges", "bytes")

	rangeHeader := c.Request().Header.Get("Range")
	if rangeHeader == "" {
		// 无 Range 请求，返回完整数据
		c.Response().Header().Set("Content-Length", strconv.Itoa(len(data)))
		return c.Blob(http.StatusOK, "video/mp2t", data)
	}

	// 解析 Range 头：bytes=start-end 或 bytes=start-
	start, end, err := parseRange(rangeHeader, len(data))
	if err != nil {
		// Range 解析失败，返回完整数据
		slog.Debug("invalid range header, returning full data", "range", rangeHeader, "error", err)
		c.Response().Header().Set("Content-Length", strconv.Itoa(len(data)))
		return c.Blob(http.StatusOK, "video/mp2t", data)
	}

	// 返回 206 Partial Content
	c.Response().Header().Set("Content-Length", strconv.Itoa(end-start+1))
	c.Response().Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, len(data)))

	slog.Debug("serving range request", "range", rangeHeader, "start", start, "end", end, "total", len(data))
	return c.Blob(http.StatusPartialContent, "video/mp2t", data[start:end+1])
}

// parseRange 解析 Range 请求头，返回 start 和 end 字节位置
// 格式：bytes=start-end 或 bytes=start-
func parseRange(rangeHeader string, totalLen int) (int, int, error) {
	// 去除 "bytes=" 前缀
	rangeSpec := strings.TrimPrefix(rangeHeader, "bytes=")
	if rangeSpec == rangeHeader {
		return 0, 0, fmt.Errorf("invalid range header: %s", rangeHeader)
	}

	parts := strings.SplitN(rangeSpec, "-", 2)
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("invalid range spec: %s", rangeSpec)
	}

	var start, end int
	var err error

	// 解析 start
	startStr := strings.TrimSpace(parts[0])
	if startStr == "" {
		start = 0
	} else {
		start, err = strconv.Atoi(startStr)
		if err != nil || start < 0 || start >= totalLen {
			return 0, 0, fmt.Errorf("invalid range start: %s", startStr)
		}
	}

	// 解析 end
	endStr := strings.TrimSpace(parts[1])
	if endStr == "" {
		end = totalLen - 1
	} else {
		end, err = strconv.Atoi(endStr)
		if err != nil || end < start || end >= totalLen {
			return 0, 0, fmt.Errorf("invalid range end: %s", endStr)
		}
	}

	return start, end, nil
}

// proxySegmentFromOrigin 反向代理透传到原始视频源 URL
// 后端作为反向代理，将请求转发到原始 TS URL，流式转发响应给客户端
// Worker 继续在后台下载缓存该分片，后续请求可命中缓存
func (h *StreamHandler) proxySegmentFromOrigin(c echo.Context, session *service.StreamSession, segmentIndex int) error {
	m3u8Info := session.GetM3U8Info()
	if segmentIndex >= len(m3u8Info.Segments) {
		return response.Fail(c, errs.New(http.StatusBadRequest, "segment index out of range"))
	}

	segURL := m3u8Info.Segments[segmentIndex].URL

	// 创建到原始视频源的请求
	req, err := http.NewRequestWithContext(c.Request().Context(), http.MethodGet, segURL, nil)
	if err != nil {
		slog.Error("create proxy request failed", "segment", segmentIndex, "url", segURL, "error", err)
		return response.Fail(c, errs.New(http.StatusBadGateway, "failed to create proxy request"))
	}

	// 透传 Range 头（让 CDN 处理 Range 请求）
	if rangeHeader := c.Request().Header.Get("Range"); rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}

	// 执行请求
	httpClient := &http.Client{Timeout: proxyTimeout}
	resp, err := httpClient.Do(req)
	if err != nil {
		slog.Error("proxy request failed", "segment", segmentIndex, "url", segURL, "error", err)
		return response.Fail(c, errs.New(http.StatusBadGateway, "failed to proxy segment"))
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		slog.Warn("proxy request returned non-OK", "segment", segmentIndex, "url", segURL, "status", resp.StatusCode)
		return response.Fail(c, errs.New(resp.StatusCode, "upstream returned error"))
	}

	// 透传关键响应头
	if contentType := resp.Header.Get("Content-Type"); contentType != "" {
		c.Response().Header().Set("Content-Type", contentType)
	} else {
		c.Response().Header().Set("Content-Type", "video/mp2t")
	}
	if contentLength := resp.Header.Get("Content-Length"); contentLength != "" {
		c.Response().Header().Set("Content-Length", contentLength)
	}
	if contentRange := resp.Header.Get("Content-Range"); contentRange != "" {
		c.Response().Header().Set("Content-Range", contentRange)
	}
	if acceptRanges := resp.Header.Get("Accept-Ranges"); acceptRanges != "" {
		c.Response().Header().Set("Accept-Ranges", acceptRanges)
	} else {
		c.Response().Header().Set("Accept-Ranges", "bytes")
	}
	c.Response().Header().Set("Cache-Control", "no-cache")

	// 写入响应状态码
	c.Response().WriteHeader(resp.StatusCode)

	// 流式转发响应体
	written, err := io.Copy(c.Response().Writer, resp.Body)
	if err != nil {
		slog.Debug("proxy stream write failed", "segment", segmentIndex, "written", written, "error", err)
	}

	slog.Debug("proxy segment from origin", "segment", segmentIndex, "status", resp.StatusCode, "written", written)
	return nil
}

// Save 保存为下载任务
// POST /api/stream/save
//func (h *StreamHandler) Save(c echo.Context) error {
//	userID := c.Get(middleware.UserIDKey).(int64)
//
//	var req request.StreamSaveReq
//	if err := c.Bind(&req); err != nil {
//		return err
//	}
//	if err := c.Validate(&req); err != nil {
//		return err
//	}
//
//	taskID, err := h.streamService.SaveAsDownload(userID, req.Session, req.VodID, req.VodName, req.EpName)
//	if err != nil {
//		return response.Fail(c, errs.New(http.StatusBadRequest, err.Error()))
//	}
//
//	return response.OK(c, response.StreamSaveResp{
//		TaskID: taskID,
//		Queued: true,
//	})
//}

// Close 关闭会话
// DELETE /api/stream/session
func (h *StreamHandler) Close(c echo.Context) error {
	var req request.StreamSessionReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	err := h.streamService.CloseSession(req.Session)
	if err != nil {
		return response.Fail(c, errs.New(http.StatusNotFound, err.Error()))
	}

	return response.OK(c, response.StreamCloseResp{
		Closed: true,
	})
}

// POST /api/stream/check 批量检测 m3u8 链接可用性
func (h *StreamHandler) CheckM3U8(c echo.Context) error {
	var req request.StreamCheckReq
	if err := c.Bind(&req); err != nil {
		return response.Fail(c, errs.New(http.StatusBadRequest, "invalid request body"))
	}
	if err := c.Validate(&req); err != nil {
		return response.Fail(c, errs.New(http.StatusBadRequest, err.Error()))
	}

	if len(req.URLs) == 0 {
		return response.Fail(c, errs.New(http.StatusBadRequest, "urls cannot be empty"))
	}
	if len(req.URLs) > 50 {
		return response.Fail(c, errs.New(http.StatusBadRequest, "too many urls, max 50"))
	}

	results := h.streamService.CheckM3U8Urls(req.URLs)

	respItems := make([]response.M3u8CheckResultItem, len(results))
	for i, r := range results {
		respItems[i] = response.M3u8CheckResultItem{
			URL:        r.URL,
			Available:  r.Available,
			StatusCode: r.StatusCode,
			Error:      r.ErrMsg,
		}
	}

	return response.OK(c, response.StreamCheckResp{
		Results: respItems,
	})
}
