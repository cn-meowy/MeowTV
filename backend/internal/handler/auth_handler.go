package handler

import (
	"log/slog"
	"time"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// AuthHandler 认证接口处理
type AuthHandler struct {
	authService *service.AuthService
}

// NewAuthHandler 创建认证 Handler
func NewAuthHandler(authService *service.AuthService) *AuthHandler {
	return &AuthHandler{authService: authService}
}

// Login 账号密码登录
// @Summary      账号密码登录
// @Description  使用用户名密码登录，返回 access_token 和 refresh_token
// @Tags         认证
// @Accept       json
// @Produce      json
// @Param        request  body      request.LoginReq       true  "登录请求"
// @Success      200      {object}  response.Response{data=response.LoginResp}
// @Failure      400      {object}  response.Response
// @Failure      401      {object}  response.Response
// @Failure      429      {object}  response.Response
// @Router       /auth/login [post]
func (h *AuthHandler) Login(c echo.Context) error {
	req := new(request.LoginReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		slog.Debug("validation error", "error", err.Error())
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	ip := c.RealIP()
	resp, err := h.authService.Login(c.Request().Context(), req, ip)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// Refresh 刷新 Token
// @Summary      刷新 Token
// @Description  使用 refresh_token 获取新的 access_token 和 refresh_token
// @Tags         认证
// @Accept       json
// @Produce      json
// @Param        request  body      request.RefreshReq     true  "刷新请求"
// @Success      200      {object}  response.Response{data=response.RefreshResp}
// @Failure      401      {object}  response.Response
// @Router       /auth/refresh [post]
func (h *AuthHandler) Refresh(c echo.Context) error {
	req := new(request.RefreshReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	resp, err := h.authService.Refresh(c.Request().Context(), req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// Logout 登出
// @Summary      登出
// @Description  将当前 access_token 加入黑名单，使其失效
// @Tags         认证
// @Accept       json
// @Produce      json
// @Security     BearerAuth
// @Success      200  {object}  response.Response
// @Failure      401  {object}  response.Response
// @Router       /auth/logout [post]
func (h *AuthHandler) Logout(c echo.Context) error {
	userID := middleware.GetUserID(c)
	jti, _ := c.Get(middleware.JTIKey).(string)
	expiresAt, _ := c.Get(middleware.ExpiresAtKey).(time.Time)
	dt, _ := c.Get(middleware.DTKey).(int8)
	deviceID := middleware.GetDeviceID(c)

	if err := h.authService.Logout(c.Request().Context(), userID, jti, expiresAt, dt, deviceID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// QRCodeRequest TV 端请求登录码
func (h *AuthHandler) QRCodeRequest(c echo.Context) error {
	req := new(request.QRCodeRequestReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		slog.Debug("qrcode request validation error", "error", err.Error())
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	resp, err := h.authService.QRCodeRequest(c.Request().Context(), req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// QRCodeScan 手机端扫码确认（纯授权操作，扫码端设备信息仅用于审计）
func (h *AuthHandler) QRCodeScan(c echo.Context) error {
	req := new(request.QRCodeScanReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	userID := middleware.GetUserID(c)
	// 扫码端信息仅用于审计，目标设备类型/ID 由 TV 端在请求码时上报，
	// 轮询时以 TV 端请求为准，避免误踢手机端
	scanDeviceID := middleware.GetDeviceID(c)
	scanDeviceName := ""

	if err := h.authService.QRCodeScan(c.Request().Context(), req, userID, scanDeviceID, scanDeviceName); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// QRCodePoll TV 端轮询登录结果
func (h *AuthHandler) QRCodePoll(c echo.Context) error {
	req := new(request.QRCodePollReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}

	resp, err := h.authService.QRCodePoll(c.Request().Context(), req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}
