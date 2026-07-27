package handler

import (
	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// AdminConfigHandler 系统配置管理接口
type AdminConfigHandler struct {
	configService *service.SysConfigService
}

// NewAdminConfigHandler 创建系统配置管理 Handler
func NewAdminConfigHandler(configService *service.SysConfigService) *AdminConfigHandler {
	return &AdminConfigHandler{configService: configService}
}

// List 获取配置列表
func (h *AdminConfigHandler) List(c echo.Context) error {
	req := new(request.ConfigListReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if req.Group != "" {
		list, err := h.configService.ListByGroup(c.Request().Context(), req.Group)
		if err != nil {
			return err
		}
		return response.OK(c, list)
	}

	list, err := h.configService.ListAll(c.Request().Context())
	if err != nil {
		return err
	}
	return response.OK(c, list)
}

// Create 创建配置项
func (h *AdminConfigHandler) Create(c echo.Context) error {
	req := new(request.ConfigCreateReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.configService.Create(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// Update 更新配置项
func (h *AdminConfigHandler) Update(c echo.Context) error {
	req := new(request.ConfigUpdateReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.configService.Update(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// Delete 删除配置项
func (h *AdminConfigHandler) Delete(c echo.Context) error {
	req := new(request.ConfigDeleteReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.configService.Delete(c.Request().Context(), req.ID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// RefreshCache 刷新配置缓存
func (h *AdminConfigHandler) RefreshCache(c echo.Context) error {
	if err := h.configService.RefreshCache(c.Request().Context()); err != nil {
		return err
	}
	return response.OKMsg(c, "缓存已刷新", nil)
}
