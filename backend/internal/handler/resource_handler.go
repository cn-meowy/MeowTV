package handler

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
	"cn.meow/meowtv/internal/util"
)

// ResourceHandler 资源模块接口
type ResourceHandler struct {
	resourceService      *service.ResourceService
	searchService        *service.SearchService
	resourceImageService *service.ResourceImageService
	configService        *service.SysConfigService
}

// NewResourceHandler 创建资源模块 Handler
func NewResourceHandler(resourceService *service.ResourceService, searchService *service.SearchService, resourceImageService *service.ResourceImageService, configService *service.SysConfigService) *ResourceHandler {
	return &ResourceHandler{
		resourceService:      resourceService,
		searchService:        searchService,
		resourceImageService: resourceImageService,
		configService:        configService,
	}
}

// ListSites 获取资源站点列表（按用户组过滤）
func (h *ResourceHandler) ListSites(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)
	role := c.Get(middleware.RoleKey).(int8)
	list, err := h.resourceService.ListSites(c.Request().Context(), userID, role)
	if err != nil {
		return err
	}
	return response.OK(c, list)
}

// GetSubscribeConfig 获取订阅配置（用户端）
func (h *ResourceHandler) GetSubscribeConfig(c echo.Context) error {
	cfg, err := h.resourceService.GetSubscribeConfig(c.Request().Context())
	if err != nil {
		return err
	}
	return response.OK(c, cfg)
}

// AdminGetSubscribeConfig 获取订阅配置（管理端）
func (h *ResourceHandler) AdminGetSubscribeConfig(c echo.Context) error {
	cfg, err := h.resourceService.GetSubscribeConfig(c.Request().Context())
	if err != nil {
		return err
	}
	return response.OK(c, cfg)
}

// AdminUpdateSubscribeConfig 更新订阅配置
func (h *ResourceHandler) AdminUpdateSubscribeConfig(c echo.Context) error {
	req := new(request.ResourceSubscribeUpdateReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.resourceService.UpdateSubscribeConfig(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OKMsg(c, "订阅配置已更新", nil)
}

// AdminFetchSubscribe 手动触发订阅拉取
func (h *ResourceHandler) AdminFetchSubscribe(c echo.Context) error {
	result, err := h.resourceService.FetchAndSaveSites(c.Request().Context())
	if err != nil {
		return err
	}
	return response.OK(c, result)
}

// Search 聚合搜索（SSE 流式推送）
func (h *ResourceHandler) Search(c echo.Context) error {
	req := new(request.SearchReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		slog.Debug("search validation error", "error", err.Error())
		return errs.WithMsg("请求参数校验失败", errs.ErrBadRequest)
	}

	userID := c.Get(middleware.UserIDKey).(int64)
	role := c.Get(middleware.RoleKey).(int8)

	eventCh, err := h.searchService.Search(c.Request().Context(), userID, role, req)
	if err != nil {
		return err
	}

	// 设置 SSE 响应头
	c.Response().Header().Set("Content-Type", "text/event-stream")
	c.Response().Header().Set("Cache-Control", "no-cache")
	c.Response().Header().Set("Connection", "keep-alive")
	c.Response().WriteHeader(http.StatusOK)

	// 流式推送事件
	for event := range eventCh {
		// SSE 格式: event: type\ndata: json\n\n
		_, _ = fmt.Fprintf(c.Response(), "event: %s\n", event.EventType)
		data, _ := json.Marshal(event.Data)
		_, _ = fmt.Fprintf(c.Response(), "data: %s\n\n", data)
		c.Response().Flush()
	}

	return nil
}

// Detail 查询资源详情
func (h *ResourceHandler) Detail(c echo.Context) error {
	req := new(request.ResourceDetailReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		return errs.WithMsg("请求参数校验失败", errs.ErrBadRequest)
	}

	userID := c.Get(middleware.UserIDKey).(int64)
	role := c.Get(middleware.RoleKey).(int8)

	detail, err := h.searchService.Detail(c.Request().Context(), userID, role, req)
	if err != nil {
		return err
	}
	return response.OK(c, detail)
}

// Paginate 资源分页查询
func (h *ResourceHandler) Paginate(c echo.Context) error {
	req := new(request.ResourcePageReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		return errs.WithMsg("请求参数校验失败", errs.ErrBadRequest)
	}

	userID := c.Get(middleware.UserIDKey).(int64)
	role := c.Get(middleware.RoleKey).(int8)

	result, err := h.searchService.Paginate(c.Request().Context(), userID, role, req)
	if err != nil {
		return err
	}
	return response.OK(c, result)
}

// ImageProxy 资源站图片代理
func (h *ResourceHandler) ImageProxy(c echo.Context) error {
	imageURL := c.QueryParam("url")
	if imageURL == "" {
		return errs.WithMsg("缺少 url 参数", errs.ErrBadRequest)
	}
	return h.resourceImageService.ProxyImage(c, imageURL)
}

// ProxyTest 测试代理连通性（管理端）
// 后端从配置中读取代理参数和测试URL，无需前端传参
func (h *ResourceHandler) ProxyTest(c echo.Context) error {
	ctx := c.Request().Context()

	// 读取代理配置
	proxyCfg := h.configService.GetValue(ctx, "resource_proxy")
	if proxyCfg == nil {
		return errs.WithMsg("代理配置不存在", errs.ErrNotFound)
	}

	enabled := strings.ToLower(proxyCfg.Value6) == "true" || proxyCfg.Value6 == "1"
	if !enabled || proxyCfg.Value2 == "" {
		return errs.WithMsg("代理未启用或地址为空", errs.ErrBadRequest)
	}

	// 读取测试URL配置
	testURL := "http://www.gstatic.com/generate_204"
	testCfg := h.configService.GetValue(ctx, "resource_proxy_test_url")
	if testCfg != nil && testCfg.Value1 != "" {
		testURL = testCfg.Value1
	}

	// 执行连通性测试
	if err := util.TestProxyConnectivity(proxyCfg.Value1, proxyCfg.Value2, proxyCfg.Value3, proxyCfg.Value4, proxyCfg.Value5, testURL); err != nil {
		return errs.WithMsg("代理连接失败: "+err.Error(), errs.ErrInternal)
	}

	return response.OKMsg(c, "代理连接成功", nil)
}
