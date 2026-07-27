package handler

import (
	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// UserHandler 用户接口处理
type UserHandler struct {
	userService *service.UserService
}

// NewUserHandler 创建用户 Handler
func NewUserHandler(userService *service.UserService) *UserHandler {
	return &UserHandler{userService: userService}
}

// Profile 获取个人信息
func (h *UserHandler) Profile(c echo.Context) error {
	userID := middleware.GetUserID(c)
	resp, err := h.userService.GetProfile(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// UpdateProfile 修改个人信息
func (h *UserHandler) UpdateProfile(c echo.Context) error {
	req := new(request.UpdateProfileReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	userID := middleware.GetUserID(c)
	if err := h.userService.UpdateProfile(c.Request().Context(), userID, req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// ChangePassword 修改密码
func (h *UserHandler) ChangePassword(c echo.Context) error {
	req := new(request.ChangePasswordReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	userID := middleware.GetUserID(c)
	if err := h.userService.ChangePassword(c.Request().Context(), userID, req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// Devices 查看在线设备
func (h *UserHandler) Devices(c echo.Context) error {
	userID := middleware.GetUserID(c)
	resp, err := h.userService.GetDevices(c.Request().Context(), userID)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// KickDevice 踢掉指定设备
func (h *UserHandler) KickDevice(c echo.Context) error {
	req := new(request.KickDeviceReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	userID := middleware.GetUserID(c)
	if err := h.userService.KickDevice(c.Request().Context(), userID, req.DeviceType); err != nil {
		return err
	}
	return response.OK(c, nil)
}
