package handler

import (
	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// AdminHandler 管理接口处理
type AdminHandler struct {
	userService *service.UserService
}

// NewAdminHandler 创建管理 Handler
func NewAdminHandler(userService *service.UserService) *AdminHandler {
	return &AdminHandler{userService: userService}
}

// CreateUser 创建用户
func (h *AdminHandler) CreateUser(c echo.Context) error {
	req := new(request.CreateUserReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	resp, err := h.userService.CreateUser(c.Request().Context(), req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// UpdateUser 编辑用户
func (h *AdminHandler) UpdateUser(c echo.Context) error {
	req := new(request.UpdateUserReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.userService.UpdateUser(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// ResetPassword 重置密码
func (h *AdminHandler) ResetPassword(c echo.Context) error {
	req := new(request.ResetPasswordReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.userService.ResetPassword(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// UserList 用户列表
func (h *AdminHandler) UserList(c echo.Context) error {
	req := new(request.UserListReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	items, total, err := h.userService.UserList(c.Request().Context(), req)
	if err != nil {
		return err
	}
	return response.OK(c, response.NewPaginated(items, total, req.Page, req.Size))
}

// DeleteUser 删除用户
func (h *AdminHandler) DeleteUser(c echo.Context) error {
	req := new(request.DeleteUserReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.userService.DeleteUser(c.Request().Context(), req.ID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// KickUser 踢用户下线
func (h *AdminHandler) KickUser(c echo.Context) error {
	req := new(request.KickUserReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.userService.KickUser(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OK(c, nil)
}
