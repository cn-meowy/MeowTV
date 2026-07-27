package service

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
	"strconv"
	"time"

	"golang.org/x/crypto/bcrypt"

	"cn.meow/meowtv/internal/auth"
	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/config"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

var usernameRegex = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)

const (
	// loginFailMax 登录失败最大次数，超过后临时锁定
	loginFailMax = 5
	// loginFailLockDuration 登录失败锁定时长
	loginFailLockDuration = 15 * time.Minute
)

// AuthService 认证业务层
type AuthService struct {
	cfg        *config.Config
	userRepo   repository.UserRepository
	jwtManager *auth.JWTManager
	blacklist  *auth.BlacklistManager
	qrcode     *auth.QRCodeManager
	cache      cache.Cache
}

// NewAuthService 创建认证 Service
func NewAuthService(
	cfg *config.Config,
	userRepo repository.UserRepository,
	jwtManager *auth.JWTManager,
	blacklist *auth.BlacklistManager,
	qrcode *auth.QRCodeManager,
	cacheProvider cache.Cache,
) *AuthService {
	return &AuthService{
		cfg:        cfg,
		userRepo:   userRepo,
		jwtManager: jwtManager,
		blacklist:  blacklist,
		qrcode:     qrcode,
		cache:      cacheProvider,
	}
}

// Login 账号密码登录
func (s *AuthService) Login(ctx context.Context, req *request.LoginReq, ip string) (*response.LoginResp, error) {
	// 1. 校验用户名格式
	if !usernameRegex.MatchString(req.Username) {
		return nil, errs.WithMsg("用户名格式不正确", errs.ErrBadRequest)
	}

	// 2. 检查登录失败次数（暴力破解防护）
	failCount, locked := s.getLoginFailCount(ctx, ip, req.Username)
	if locked {
		slog.Warn("login blocked due to too many failures",
			"ip", ip, "username", req.Username, "fail_count", failCount)
		return nil, errs.WithMsg(fmt.Sprintf("登录失败次数过多，请%d分钟后再试", int(loginFailLockDuration.Minutes())), errs.ErrTooManyReq)
	}

	// 3. 查询用户
	user, err := s.userRepo.GetByUsername(ctx, req.Username)
	if err != nil {
		s.incrementLoginFail(ctx, ip, req.Username)
		return nil, errs.WithMsg("用户名或密码错误", errs.ErrBadRequest)
	}

	// 4. 校验用户状态
	if user.Status != entity.StatusEnabled {
		return nil, errs.WithMsg("账号已被禁用", errs.ErrForbidden)
	}

	// 5. 验证密码
	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		s.incrementLoginFail(ctx, ip, req.Username)
		return nil, errs.WithMsg("用户名或密码错误", errs.ErrBadRequest)
	}

	// 6. 登录成功，清除失败计数
	s.clearLoginFailCount(ctx, ip, req.Username)

	// 7. 处理同设备互踢（仍按 deviceType 互踢）
	if s.cfg.Auth.KickEnabled {
		dt := entity.DeviceType(req.DeviceType)
		dtInt8 := int8(dt)
		if err := s.blacklist.KickByDeviceType(ctx, user.ID, &dtInt8); err != nil {
			return nil, errs.Wrap(err, errs.ErrInternal)
		}
	}

	// 8. 签发 Token（含 deviceID）
	slog.Info("user logged in", "user_id", user.ID, "device_type", req.DeviceType, "device_id", req.DeviceID, "ip", ip)
	accessToken, accessClaims, err := s.jwtManager.GenerateAccessToken(user.ID, int8(user.Role), req.DeviceType, req.DeviceID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	refreshToken, refreshClaims, err := s.jwtManager.GenerateRefreshToken(user.ID, int8(user.Role), req.DeviceType, req.DeviceID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 9. 记录设备会话
	if err := s.blacklist.AddDeviceSession(ctx, user.ID, req.DeviceID, int8(req.DeviceType), req.DeviceName, accessClaims.JTI, refreshClaims.JTI); err != nil {
		slog.Error("failed to add device session", "user_id", user.ID, "device_id", req.DeviceID, "error", err)
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 10. 更新最后登录时间
	if err := s.userRepo.UpdateLastLogin(ctx, user.ID); err != nil {
		slog.Warn("failed to update last login time", "user_id", user.ID, "error", err)
	}

	return &response.LoginResp{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int64(s.cfg.Auth.AccessTTL.Seconds()),
	}, nil
}

// getLoginFailCount 获取登录失败次数，返回 (失败次数, 是否被锁定)
func (s *AuthService) getLoginFailCount(ctx context.Context, ip, username string) (int, bool) {
	ck := cache.KeyLoginFailCount(ip, username)
	val, err := s.cache.Get(ctx, ck.Key)
	if err != nil || val == "" {
		return 0, false
	}
	count, err := strconv.Atoi(val)
	if err != nil {
		return 0, false
	}
	return count, count >= loginFailMax
}

// incrementLoginFail 增加登录失败计数
func (s *AuthService) incrementLoginFail(ctx context.Context, ip, username string) {
	ck := cache.KeyLoginFailCount(ip, username)
	newCount, err := s.cache.Incr(ctx, ck.Key)
	if err != nil {
		_ = s.cache.Set(ctx, ck.Key, "1", ck.TTL)
		return
	}
	if newCount == 1 {
		_ = s.cache.Expire(ctx, ck.Key, ck.TTL)
	}
}

// clearLoginFailCount 清除登录失败计数
func (s *AuthService) clearLoginFailCount(ctx context.Context, ip, username string) {
	ck := cache.KeyLoginFailCount(ip, username)
	_ = s.cache.Delete(ctx, ck.Key)
}

// Refresh 刷新 Token
func (s *AuthService) Refresh(ctx context.Context, req *request.RefreshReq) (*response.RefreshResp, error) {
	// 1. 验证 Refresh Token
	claims, err := s.jwtManager.VerifyToken(req.RefreshToken)
	if err != nil {
		return nil, errs.WithMsg("无效的刷新令牌", errs.ErrUnauthorized)
	}

	// 2. 检查黑名单
	blacklisted, err := s.blacklist.IsBlacklisted(ctx, claims.JTI)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}
	if blacklisted {
		return nil, errs.WithMsg("刷新令牌已失效", errs.ErrUnauthorized)
	}

	// 3. 旧 Refresh Token 加入黑名单
	remainingTTL := time.Until(claims.ExpiresAt.Time)
	if err := s.blacklist.AddToBlacklist(ctx, claims.JTI, remainingTTL); err != nil {
		slog.Warn("failed to blacklist old refresh token", "jti", claims.JTI, "error", err)
	}

	// 4. 签发新 Token（保留 deviceID 和 deviceType）
	accessToken, accessClaims, err := s.jwtManager.GenerateAccessToken(claims.UserID, claims.Role, claims.DeviceType, claims.DeviceID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	refreshToken, refreshClaims, err := s.jwtManager.GenerateRefreshToken(claims.UserID, claims.Role, claims.DeviceType, claims.DeviceID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 5. 更新设备会话中的 jti
	session, _ := s.blacklist.GetDeviceSession(ctx, claims.UserID, claims.DeviceType, claims.DeviceID)
	if session != nil && session.RefreshJTI == claims.JTI {
		// 获取旧的 access jti 并加入黑名单
		_ = s.blacklist.AddToBlacklist(ctx, session.AccessJTI, cache.TTLTokenBlack)

		// 更新 session 中的 jti
		_ = s.blacklist.AddDeviceSession(ctx, claims.UserID, claims.DeviceID, claims.DeviceType, session.DeviceName, accessClaims.JTI, refreshClaims.JTI)
	} else if session == nil {
		// 设备会话已过期但 refresh_token 仍有效，重新创建 session
		// 否则新签发的 access_token 无法通过 IsTokenActive 验证，导致 401 → refresh 无限循环
		slog.Info("device session expired, recreating on refresh",
			"user_id", claims.UserID, "device_type", claims.DeviceType, "device_id", claims.DeviceID)
		_ = s.blacklist.AddDeviceSession(ctx, claims.UserID, claims.DeviceID, claims.DeviceType, "", accessClaims.JTI, refreshClaims.JTI)
	}

	return &response.RefreshResp{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    int64(s.cfg.Auth.AccessTTL.Seconds()),
	}, nil
}

// Logout 登出
func (s *AuthService) Logout(ctx context.Context, userID int64, accessJTI string, accessExpiresAt time.Time, deviceType int8, deviceID string) error {
	// 1. 将 Access Token 加入黑名单
	accessTTL := time.Until(accessExpiresAt)
	if accessTTL <= 0 {
		accessTTL = time.Minute
	}
	if err := s.blacklist.AddToBlacklist(ctx, accessJTI, accessTTL); err != nil {
		slog.Warn("failed to blacklist access token on logout", "jti", accessJTI, "error", err)
	}

	// 2. 获取设备会话，将 refresh jti 也加入黑名单
	session, _ := s.blacklist.GetDeviceSession(ctx, userID, deviceType, deviceID)
	if session != nil {
		_ = s.blacklist.AddToBlacklist(ctx, session.RefreshJTI, cache.TTLTokenBlack)
		_ = s.blacklist.AddToBlacklist(ctx, session.AccessJTI, cache.TTLTokenBlack)
	}

	// 3. 删除设备会话
	_ = s.blacklist.RemoveDeviceSession(ctx, userID, deviceType, deviceID)

	return nil
}

// QRCodeRequest TV 端请求登录码
func (s *AuthService) QRCodeRequest(ctx context.Context, req *request.QRCodeRequestReq) (*response.QRCodeRequestResp, error) {
	code, err := s.qrcode.GenerateCode(ctx, req.DeviceID, req.DeviceName, *req.DeviceType)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	qrURL := fmt.Sprintf("meowtv://qr-login?code=%s", code)

	return &response.QRCodeRequestResp{
		Code:      code,
		QRURL:     qrURL,
		ExpiresIn: int64(cache.TTLLoginCode.Seconds()),
	}, nil
}

// QRCodeScan 手机端扫码确认（纯授权，扫码端设备信息仅用于审计）
func (s *AuthService) QRCodeScan(ctx context.Context, req *request.QRCodeScanReq, userID int64, scanDeviceID string, scanDeviceName string) error {
	if err := s.qrcode.ScanCode(ctx, req.Code, userID, scanDeviceID, scanDeviceName); err != nil {
		return errs.WithMsg(err.Error(), errs.ErrBadRequest)
	}
	return nil
}

// QRCodePoll TV 端轮询登录结果
func (s *AuthService) QRCodePoll(ctx context.Context, req *request.QRCodePollReq) (*response.QRCodePollResp, error) {
	data, err := s.qrcode.PollCode(ctx, req.Code)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	resp := &response.QRCodePollResp{
		Status: data.Status,
	}

	if data.Status == "confirmed" {
		// 以 TV 端轮询请求中的设备信息为唯一真实来源
		// （扫码端信息只用于审计，避免误踢手机端）
		data.DeviceID = req.DeviceID
		data.DeviceName = req.DeviceName
		data.DeviceType = *req.DeviceType

		// 查询用户信息获取 role
		user, err := s.userRepo.GetByID(ctx, data.UserID)
		if err != nil {
			return nil, errs.WithMsg("用户不存在", errs.ErrNotFound)
		}

		// 处理同设备类型互踢（仅踢 TV 端同类型设备，手机端不受影响）
		if s.cfg.Auth.KickEnabled {
			dtInt8 := data.DeviceType
			if err := s.blacklist.KickByDeviceType(ctx, data.UserID, &dtInt8); err != nil {
				slog.Warn("failed to kick by device type on qr login", "user_id", data.UserID, "error", err)
			}
		}

		// 签发 Token（使用真实 role，含 TV 端 deviceType 与 deviceID）
		accessToken, accessClaims, err := s.jwtManager.GenerateAccessToken(data.UserID, int8(user.Role), data.DeviceType, data.DeviceID)
		if err != nil {
			return nil, errs.Wrap(err, errs.ErrInternal)
		}

		refreshToken, refreshClaims, err := s.jwtManager.GenerateRefreshToken(data.UserID, int8(user.Role), data.DeviceType, data.DeviceID)
		if err != nil {
			return nil, errs.Wrap(err, errs.ErrInternal)
		}

		if err := s.blacklist.AddDeviceSession(ctx, data.UserID, data.DeviceID, data.DeviceType, data.DeviceName, accessClaims.JTI, refreshClaims.JTI); err != nil {
			slog.Warn("failed to add device session on qr login", "jti", accessClaims.JTI, "error", err)
		}

		resp.AccessToken = accessToken
		resp.RefreshToken = refreshToken
		resp.ExpiresIn = int64(s.cfg.Auth.AccessTTL.Seconds())

		// 更新最后登录时间
		if err := s.userRepo.UpdateLastLogin(ctx, data.UserID); err != nil {
			slog.Warn("failed to update last login time on qr login", "user_id", data.UserID, "error", err)
		}
	}

	return resp, nil
}
