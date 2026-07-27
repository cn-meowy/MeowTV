package auth

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"fmt"

	"cn.meow/meowtv/internal/cache"
)

// QRCodeData 扫码登录数据
type QRCodeData struct {
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name,omitempty"`
	Status     string `json:"status"` // waiting / confirmed / expired
	UserID     int64  `json:"user_id,omitempty"`
	DeviceType int8   `json:"device_type,omitempty"` // 目标设备类型（TV 端上报）
	// 扫码端信息，仅用于审计，不参与互踢与签发
	ScanDeviceID   string `json:"scan_device_id,omitempty"`
	ScanDeviceName string `json:"scan_device_name,omitempty"`
}

// QRCodeManager 扫码登录管理器
type QRCodeManager struct {
	cache cache.Cache
}

// NewQRCodeManager 创建扫码登录管理器
func NewQRCodeManager(c cache.Cache) *QRCodeManager {
	return &QRCodeManager{cache: c}
}

// GenerateCode 生成8位登录码，deviceType 为目标设备（TV 端）类型
func (m *QRCodeManager) GenerateCode(ctx context.Context, deviceID string, deviceName string, deviceType int8) (string, error) {
	code := generateRandomCode()
	data := QRCodeData{
		DeviceID:   deviceID,
		DeviceName: deviceName,
		DeviceType: deviceType,
		Status:     "waiting",
	}
	dataBytes, _ := json.Marshal(data)
	ck := cache.KeyLoginCode(code)
	if err := m.cache.Set(ctx, ck.Key, string(dataBytes), ck.TTL); err != nil {
		return "", fmt.Errorf("failed to store login code: %w", err)
	}
	return code, nil
}

// ScanCode 扫码确认，仅授权并记录扫码端信息，不修改目标设备类型/ID/Name
func (m *QRCodeManager) ScanCode(ctx context.Context, code string, userID int64, scanDeviceID string, scanDeviceName string) error {
	ck := cache.KeyLoginCode(code)
	dataStr, err := m.cache.Get(ctx, ck.Key)
	if err != nil || dataStr == "" {
		return fmt.Errorf("login code expired or invalid")
	}

	var data QRCodeData
	if err := json.Unmarshal([]byte(dataStr), &data); err != nil {
		return fmt.Errorf("invalid login code data")
	}

	if data.Status != "waiting" {
		return fmt.Errorf("login code already used")
	}

	data.Status = "confirmed"
	data.UserID = userID
	// 仅记录扫码端信息用于审计，目标设备信息（DeviceType/DeviceID/DeviceName）
	// 由 TV 端在请求码时上报，轮询时用 req 覆盖，避免误踢扫码端
	data.ScanDeviceID = scanDeviceID
	data.ScanDeviceName = scanDeviceName

	dataBytes, _ := json.Marshal(data)
	if err := m.cache.Set(ctx, ck.Key, string(dataBytes), ck.TTL); err != nil {
		return fmt.Errorf("failed to update login code: %w", err)
	}

	return nil
}

// PollCode 轮询登录码状态
func (m *QRCodeManager) PollCode(ctx context.Context, code string) (*QRCodeData, error) {
	ck := cache.KeyLoginCode(code)
	dataStr, err := m.cache.Get(ctx, ck.Key)
	if err != nil || dataStr == "" {
		return &QRCodeData{Status: "expired"}, nil
	}

	var data QRCodeData
	if err := json.Unmarshal([]byte(dataStr), &data); err != nil {
		return &QRCodeData{Status: "expired"}, nil
	}

	// 确认后删除登录码，防止重复使用
	if data.Status == "confirmed" {
		_ = m.cache.Delete(ctx, ck.Key)
	}

	return &data, nil
}

// generateRandomCode 生成8位字母数字混合码
// 使用大写字母+数字，避免容易混淆的字符（0/O, 1/I/L）
const codeAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

func generateRandomCode() string {
	b := make([]byte, 8)
	randBytes := make([]byte, 8)
	_, _ = rand.Read(randBytes)
	for i := range b {
		b[i] = codeAlphabet[int(randBytes[i])%len(codeAlphabet)]
	}
	return string(b)
}
