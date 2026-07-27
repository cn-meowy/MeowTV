package middleware

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/auth"
	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/entity"
)

const (
	// UserIDKey is the context key for the authenticated user ID.
	UserIDKey = "user_id"
	// RoleKey is the context key for the user role.
	RoleKey = "role"
	// JTIKey is the context key for the token JTI.
	JTIKey = "jti"
	// DTKey is the context key for the device type.
	DTKey = "device_type"
	// DeviceIDKey is the context key for the device ID.
	DeviceIDKey = "device_id"
	// ExpiresAtKey is the context key for the token expiration time.
	ExpiresAtKey = "expires_at"
	// BearerTokenKey is the context key for the raw JWT token string.
	BearerTokenKey = "bearer_token"
	// TempTokenKey is the context key for the verified temporary token.
	TempTokenKey = "temp_token"
)

// tempTokenData is the JSON value stored in cache for a temporary token.
type tempTokenData struct {
	CreatedAt int64 `json:"created_at"` // Unix timestamp in seconds
}

// NewAuthMiddleware creates authentication middlewares with explicit dependencies.
type NewAuthMiddleware struct {
	jwtMgr   *auth.JWTManager
	blackMgr *auth.BlacklistManager
}

// NewAuthProviders creates a new AuthMiddleware with the given JWT manager and blacklist manager.
func NewAuthProviders(j *auth.JWTManager, b *auth.BlacklistManager) *NewAuthMiddleware {
	return &NewAuthMiddleware{jwtMgr: j, blackMgr: b}
}

// Auth returns an authentication middleware that verifies JWT tokens.
func (m *NewAuthMiddleware) Auth() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if err := m.verifyAuth(c); err != nil {
				return err
			}
			return next(c)
		}
	}
}

// AuthAdmin returns an authentication middleware that verifies JWT tokens
// and requires the user to be an admin.
func (m *NewAuthMiddleware) AuthAdmin() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			if err := m.verifyAuth(c); err != nil {
				return err
			}

			role := c.Get(RoleKey).(int8)
			if entity.Role(role) != entity.RoleAdmin {
				return errs.ErrForbidden
			}

			return next(c)
		}
	}
}

// verifyAuth is the core verification logic shared by Auth and AuthAdmin.
func (m *NewAuthMiddleware) verifyAuth(c echo.Context) error {
	// 1. Extract Bearer Token (Authorization header only)
	tokenStr := extractBearerToken(c)
	if tokenStr == "" {
		return errs.ErrUnauthorized
	}

	// 2. Verify JWT signature and expiration
	claims, err := m.jwtMgr.VerifyToken(tokenStr)
	if err != nil {
		return errs.ErrUnauthorized
	}

	// 3. Check token blacklist
	blacklisted, err := m.blackMgr.IsBlacklisted(c.Request().Context(), claims.JTI)
	if err != nil {
		return errs.ErrUnauthorized
	}
	if blacklisted {
		return errs.ErrUnauthorized
	}

	// 4. Check token in user active sessions
	active, err := m.blackMgr.IsTokenActive(c.Request().Context(), claims.UserID, claims.JTI)
	if err != nil || !active {
		return errs.ErrUnauthorized
	}

	// 5. Update device session heartbeat (refresh last_active_at + TTL)
	if claims.DeviceID != "" {
		_ = m.blackMgr.RefreshSessionHeartbeat(c.Request().Context(), claims.UserID, claims.DeviceType, claims.DeviceID)
	}

	// 6. Set context values
	c.Set(UserIDKey, claims.UserID)
	c.Set(RoleKey, claims.Role)
	c.Set(JTIKey, claims.JTI)
	c.Set(DTKey, claims.DeviceType)
	c.Set(DeviceIDKey, claims.DeviceID)
	c.Set(ExpiresAtKey, claims.ExpiresAt.Time)
	c.Set(BearerTokenKey, tokenStr)

	return nil
}

// extractBearerToken extracts the Bearer token from the Authorization header only.
// URL query parameter token is handled by TempTokenAuth middleware instead.
func extractBearerToken(c echo.Context) string {
	authHeader := c.Request().Header.Get("Authorization")
	if len(authHeader) > 7 && strings.HasPrefix(authHeader, "Bearer ") {
		return authHeader[7:]
	}
	return ""
}

// GetUserID extracts the authenticated user ID from the Echo context.
func GetUserID(c echo.Context) int64 {
	if uid, ok := c.Get(UserIDKey).(int64); ok {
		return uid
	}
	return 0
}

// GetRole extracts the user role from the Echo context.
func GetRole(c echo.Context) entity.Role {
	if r, ok := c.Get(RoleKey).(int8); ok {
		return entity.Role(r)
	}
	return entity.RoleUser
}

// GetDeviceID extracts the device ID from the Echo context.
func GetDeviceID(c echo.Context) string {
	if did, ok := c.Get(DeviceIDKey).(string); ok {
		return did
	}
	return ""
}

// GetExpiresAt extracts the token expiration time from the Echo context.
func GetExpiresAt(c echo.Context) interface{} {
	return c.Get(ExpiresAtKey)
}

// IsAuthenticated checks whether the current request is authenticated.
func IsAuthenticated(c echo.Context) bool {
	return GetUserID(c) > 0
}

// NewTempTokenAuth creates a middleware that verifies temporary tokens from URL query parameter.
// Temporary tokens are stored in cache with JSON value containing created_at timestamp.
// On each valid request, the token TTL is renewed (up to TTLTempTokenMax from creation time).
func NewTempTokenAuth(c cache.Cache) echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(ctx echo.Context) error {
			token := ctx.QueryParam("token")
			if token == "" {
				return errs.ErrUnauthorized
			}

			ck := cache.KeyTempToken(token)
			val, err := c.Get(ctx.Request().Context(), ck.Key)
			if err != nil || val == "" {
				return errs.ErrUnauthorized
			}

			// Parse token data to check max lifetime
			var data tempTokenData
			if err := json.Unmarshal([]byte(val), &data); err != nil {
				// Legacy format or corrupt data, treat as invalid
				_ = c.Delete(ctx.Request().Context(), ck.Key)
				return errs.ErrUnauthorized
			}

			// Check if token has exceeded max lifetime
			createdAt := time.Unix(data.CreatedAt, 0)
			if time.Since(createdAt) > cache.TTLTempTokenMax {
				_ = c.Delete(ctx.Request().Context(), ck.Key)
				return errs.ErrUnauthorized
			}

			// Renew TTL on each valid request
			_ = c.Set(ctx.Request().Context(), ck.Key, val, ck.TTL)

			// Store verified token in context
			ctx.Set(TempTokenKey, token)
			return next(ctx)
		}
	}
}

// GetTempToken extracts the verified temporary token from the Echo context.
func GetTempToken(c echo.Context) string {
	if t, ok := c.Get(TempTokenKey).(string); ok {
		return t
	}
	return ""
}

// GetBearerToken extracts the raw JWT token string from the Echo context.
func GetBearerToken(c echo.Context) string {
	if t, ok := c.Get(BearerTokenKey).(string); ok {
		return t
	}
	return ""
}
