package handler

import (
	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// AdminGroupHandler 管理员用户组接口
type AdminGroupHandler struct {
	groupService *service.UserGroupService
}

// NewAdminGroupHandler 创建管理员用户组 Handler
func NewAdminGroupHandler(groupService *service.UserGroupService) *AdminGroupHandler {
	return &AdminGroupHandler{groupService: groupService}
}

// Create 创建用户组
func (h *AdminGroupHandler) Create(c echo.Context) error {
	req := new(request.CreateGroupReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	resp, err := h.groupService.CreateGroup(c.Request().Context(), req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// Update 更新用户组
func (h *AdminGroupHandler) Update(c echo.Context) error {
	req := new(request.UpdateGroupReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.groupService.UpdateGroup(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OKMsg(c, "用户组已更新", nil)
}

// Delete 删除用户组
func (h *AdminGroupHandler) Delete(c echo.Context) error {
	req := new(request.DeleteGroupReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.groupService.DeleteGroup(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OKMsg(c, "用户组已删除", nil)
}

// List 用户组列表
func (h *AdminGroupHandler) List(c echo.Context) error {
	req := new(request.GroupListReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	result, err := h.groupService.ListGroups(c.Request().Context(), req)
	if err != nil {
		return err
	}
	return response.OK(c, result)
}

// Detail 用户组详情
func (h *AdminGroupHandler) Detail(c echo.Context) error {
	req := new(request.GroupDetailReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	resp, err := h.groupService.GetGroupDetail(c.Request().Context(), req.ID)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// SetResources 设置用户组关联资源站点
func (h *AdminGroupHandler) SetResources(c echo.Context) error {
	req := new(request.SetGroupResourcesReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.groupService.SetGroupResources(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OKMsg(c, "用户组资源已更新", nil)
}

// SetUserGroup 设置用户所属用户组
func (h *AdminGroupHandler) SetUserGroup(c echo.Context) error {
	req := new(request.SetUserGroupReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	if err := h.groupService.SetUserGroup(c.Request().Context(), req); err != nil {
		return err
	}
	return response.OKMsg(c, "用户所属用户组已更新", nil)
}
