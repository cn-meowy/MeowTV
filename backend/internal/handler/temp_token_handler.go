package handler

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"time"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/response"
)

// TempTokenHandler 通用临时 Token 接口
type TempTokenHandler struct {
	cache cache.Cache
}

// NewTempTokenHandler 创建通用临时 Token Handler
func NewTempTokenHandler(cache cache.Cache) *TempTokenHandler {
	return &TempTokenHandler{cache: cache}
}

// Generate 生成通用临时 Token
// GET /api/token/temp（需 JWT Auth 认证）
func (h *TempTokenHandler) Generate(c echo.Context) error {
	token, err := GenerateTempToken(c, h.cache)
	if err != nil {
		return err
	}
	return response.OK(c, response.TempTokenResp{
		Token:     token,
		ExpiresIn: int(cache.TTLTempToken.Seconds()),
	})
}

// GenerateTempToken 生成临时 token 并存入缓存
// 缓存值格式为 JSON：{"created_at": 1234567890}
// 此函数为包级导出函数，供其他 handler 复用
func GenerateTempToken(c echo.Context, cacheInstance cache.Cache) (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", errs.Wrap(err, errs.ErrInternal)
	}
	token := hex.EncodeToString(bytes)

	// 存入缓存，值为 JSON 格式含 created_at 时间戳
	data := TempTokenData{CreatedAt: time.Now().Unix()}
	jsonBytes, err := json.Marshal(data)
	if err != nil {
		return "", errs.Wrap(err, errs.ErrInternal)
	}

	ck := cache.KeyTempToken(token)
	_ = cacheInstance.Set(c.Request().Context(), ck.Key, string(jsonBytes), ck.TTL)

	return token, nil
}

// TempTokenData 临时 token 缓存数据（导出供中间件使用）
type TempTokenData struct {
	CreatedAt int64 `json:"created_at"` // Unix timestamp in seconds
}
