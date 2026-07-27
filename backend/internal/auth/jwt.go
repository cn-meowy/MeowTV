package auth

import (
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"

	"cn.meow/meowtv/internal/config"
)

// Claims JWT 载荷
type Claims struct {
	UserID     int64  `json:"uid"`
	Role       int8   `json:"role"`
	DeviceType int8   `json:"dt"`
	DeviceID   string `json:"did"`
	JTI        string `json:"jti"`
	jwt.RegisteredClaims
}

// JWTManager JWT 管理器
type JWTManager struct {
	cfg *config.AuthConfig
}

// NewJWTManager 创建 JWT 管理器
func NewJWTManager(cfg *config.AuthConfig) *JWTManager {
	return &JWTManager{cfg: cfg}
}

// GenerateAccessToken 签发 Access Token
func (m *JWTManager) GenerateAccessToken(userID int64, role int8, deviceType int8, deviceID string) (string, *Claims, error) {
	now := time.Now()
	jti := uuid.New().String()
	claims := &Claims{
		UserID:     userID,
		Role:       role,
		DeviceType: deviceType,
		DeviceID:   deviceID,
		JTI:        jti,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        jti,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.cfg.AccessTTL)),
			Issuer:    "meowtv",
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	jwtSecret, err := m.cfg.JWTSecret.Plain()
	if err != nil {
		return "", nil, fmt.Errorf("failed to decrypt JWT secret: %w", err)
	}
	tokenStr, err := token.SignedString([]byte(jwtSecret))
	if err != nil {
		return "", nil, fmt.Errorf("failed to sign access token: %w", err)
	}
	return tokenStr, claims, nil
}

// GenerateRefreshToken 签发 Refresh Token
func (m *JWTManager) GenerateRefreshToken(userID int64, role int8, deviceType int8, deviceID string) (string, *Claims, error) {
	now := time.Now()
	jti := uuid.New().String()
	claims := &Claims{
		UserID:     userID,
		Role:       role,
		DeviceType: deviceType,
		DeviceID:   deviceID,
		JTI:        jti,
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        jti,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(m.cfg.RefreshTTL)),
			Issuer:    "meowtv",
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	jwtSecret, err := m.cfg.JWTSecret.Plain()
	if err != nil {
		return "", nil, fmt.Errorf("failed to decrypt JWT secret: %w", err)
	}
	tokenStr, err := token.SignedString([]byte(jwtSecret))
	if err != nil {
		return "", nil, fmt.Errorf("failed to sign refresh token: %w", err)
	}
	return tokenStr, claims, nil
}

// VerifyToken 验证 Token，返回 Claims
func (m *JWTManager) VerifyToken(tokenStr string) (*Claims, error) {
	jwtSecret, err := m.cfg.JWTSecret.Plain()
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt JWT secret: %w", err)
	}
	token, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return []byte(jwtSecret), nil
	})
	if err != nil {
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}
	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}
	return claims, nil
}
