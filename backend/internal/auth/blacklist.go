package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"cn.meow/meowtv/internal/cache"
)

// BlacklistManager Token 黑名单 + 设备会话管理器
type BlacklistManager struct {
	cache            cache.Cache
	deviceSessionTTL time.Duration // 设备会话心跳超时时间（可配置）
}

// NewBlacklistManager 创建黑名单管理器
func NewBlacklistManager(c cache.Cache, deviceSessionTTL time.Duration) *BlacklistManager {
	if deviceSessionTTL <= 0 {
		deviceSessionTTL = cache.TTLDeviceSession
	}
	return &BlacklistManager{cache: c, deviceSessionTTL: deviceSessionTTL}
}

// DeviceSessionData 设备会话数据（存储在缓存中）
type DeviceSessionData struct {
	DeviceType   int8   `json:"device_type"`
	DeviceName   string `json:"device_name"`
	AccessJTI    string `json:"access_jti"`
	RefreshJTI   string `json:"refresh_jti"`
	LastActiveAt int64  `json:"last_active_at"`
}

// DeviceSummaryEntry 设备汇总条目（存储在 user:devices:{uid} 中）
type DeviceSummaryEntry struct {
	DeviceID     string `json:"device_id"`
	DeviceName   string `json:"device_name"`
	DeviceType   int8   `json:"device_type"`
	LastActiveAt int64  `json:"last_active_at"`
	Online       bool   `json:"-"` // 不序列化到缓存，仅用于 API 响应
}

// UserDevicesSummary 用户设备汇总索引，key 为 device_type 字符串
type UserDevicesSummary map[string]DeviceSummaryEntry

// ── 黑名单操作 ──────────────────────────────────────────────────────────────

// AddToBlacklist 将 Token 加入黑名单
func (m *BlacklistManager) AddToBlacklist(ctx context.Context, jti string, ttl time.Duration) error {
	ck := cache.KeyTokenBlack(jti)
	if ttl > cache.TTLTokenBlack {
		ttl = cache.TTLTokenBlack
	}
	if ttl <= 0 {
		ttl = time.Minute
	}
	return m.cache.Set(ctx, ck.Key, "1", ttl)
}

// IsBlacklisted 检查 Token 是否在黑名单中
func (m *BlacklistManager) IsBlacklisted(ctx context.Context, jti string) (bool, error) {
	ck := cache.KeyTokenBlack(jti)
	return m.cache.Exists(ctx, ck.Key)
}

// ── 设备会话操作 ────────────────────────────────────────────────────────────

// AddDeviceSession 创建设备会话，写入 session 缓存 + 更新汇总索引
func (m *BlacklistManager) AddDeviceSession(ctx context.Context, userID int64, deviceID string, deviceType int8, deviceName string, accessJTI, refreshJTI string) error {
	now := time.Now().Unix()

	// 1. 写入设备会话
	session := DeviceSessionData{
		DeviceType:   deviceType,
		DeviceName:   deviceName,
		AccessJTI:    accessJTI,
		RefreshJTI:   refreshJTI,
		LastActiveAt: now,
	}
	sessionData, _ := json.Marshal(session)
	ck := cache.KeyDeviceSession(userID, deviceType, deviceID, m.deviceSessionTTL)
	if err := m.cache.Set(ctx, ck.Key, string(sessionData), ck.TTL); err != nil {
		return fmt.Errorf("failed to set device session: %w", err)
	}

	// 2. 更新汇总索引
	if err := m.updateDevicesSummary(ctx, userID, deviceID, deviceType, deviceName, now); err != nil {
		return fmt.Errorf("failed to update devices summary: %w", err)
	}

	return nil
}

// GetDeviceSession 获取设备会话数据
func (m *BlacklistManager) GetDeviceSession(ctx context.Context, userID int64, deviceType int8, deviceID string) (*DeviceSessionData, error) {
	ck := cache.KeyDeviceSession(userID, deviceType, deviceID, m.deviceSessionTTL)
	data, err := m.cache.Get(ctx, ck.Key)
	if err != nil || data == "" {
		return nil, nil // session 不存在即设备离线
	}
	var session DeviceSessionData
	if err := json.Unmarshal([]byte(data), &session); err != nil {
		return nil, nil
	}
	return &session, nil
}

// RemoveDeviceSession 删除设备会话 + 更新汇总索引
func (m *BlacklistManager) RemoveDeviceSession(ctx context.Context, userID int64, deviceType int8, deviceID string) error {
	// 1. 删除 session
	ck := cache.KeyDeviceSession(userID, deviceType, deviceID, m.deviceSessionTTL)
	_ = m.cache.Delete(ctx, ck.Key)

	// 2. 更新汇总索引（移除该设备）
	_ = m.removeFromDevicesSummary(ctx, userID, deviceType)

	return nil
}

// RefreshSessionHeartbeat 更新设备会话心跳（last_active_at + 重置 TTL）
func (m *BlacklistManager) RefreshSessionHeartbeat(ctx context.Context, userID int64, deviceType int8, deviceID string) error {
	// 1. 获取当前 session
	ck := cache.KeyDeviceSession(userID, deviceType, deviceID, m.deviceSessionTTL)
	data, err := m.cache.Get(ctx, ck.Key)
	if err != nil || data == "" {
		return nil // session 不存在，跳过心跳更新
	}

	var session DeviceSessionData
	if err := json.Unmarshal([]byte(data), &session); err != nil {
		return nil
	}

	// 2. 更新 last_active_at 并重置 TTL
	session.LastActiveAt = time.Now().Unix()
	sessionData, _ := json.Marshal(session)
	if err := m.cache.Set(ctx, ck.Key, string(sessionData), ck.TTL); err != nil {
		return fmt.Errorf("failed to refresh session heartbeat: %w", err)
	}

	// 3. 更新汇总索引中的 last_active_at
	_ = m.updateDevicesSummary(ctx, userID, deviceID, deviceType, session.DeviceName, session.LastActiveAt)

	return nil
}

// ── 互踢操作 ────────────────────────────────────────────────────────────────

// KickByDeviceType 踢掉指定用户指定设备类型的所有设备
// 如果 deviceType 为 nil，则踢掉所有设备
func (m *BlacklistManager) KickByDeviceType(ctx context.Context, userID int64, deviceType *int8) error {
	summary, err := m.getUserDevicesSummary(ctx, userID)
	if err != nil || len(summary) == 0 {
		return nil
	}

	var remaining UserDevicesSummary = make(map[string]DeviceSummaryEntry)

	for dtKey, entry := range summary {
		if deviceType != nil && entry.DeviceType != *deviceType {
			remaining[dtKey] = entry
			continue
		}
		// 踢掉该设备：将 jti 加入黑名单 + 删除 session
		session, _ := m.GetDeviceSession(ctx, userID, entry.DeviceType, entry.DeviceID)
		if session != nil {
			_ = m.AddToBlacklist(ctx, session.AccessJTI, cache.TTLTokenBlack)
			_ = m.AddToBlacklist(ctx, session.RefreshJTI, cache.TTLTokenBlack)
		}
		ck := cache.KeyDeviceSession(userID, entry.DeviceType, entry.DeviceID, m.deviceSessionTTL)
		_ = m.cache.Delete(ctx, ck.Key)
	}

	// 更新汇总索引
	ck := cache.KeyUserDevices(userID)
	if len(remaining) == 0 {
		_ = m.cache.Delete(ctx, ck.Key)
	} else {
		data, _ := json.Marshal(remaining)
		_ = m.cache.Set(ctx, ck.Key, string(data), ck.TTL)
	}

	return nil
}

// GetUserDevices 获取用户所有设备列表（从汇总索引读取，检查 session 存活性）
func (m *BlacklistManager) GetUserDevices(ctx context.Context, userID int64) ([]DeviceSummaryEntry, error) {
	summary, err := m.getUserDevicesSummary(ctx, userID)
	if err != nil {
		return nil, err
	}

	var devices []DeviceSummaryEntry
	for _, entry := range summary {
		// 检查 session 是否存在（判断在线状态）
		session, _ := m.GetDeviceSession(ctx, userID, entry.DeviceType, entry.DeviceID)
		online := session != nil
		if online {
			entry.LastActiveAt = session.LastActiveAt
		}
		entry.Online = online // 注意：DeviceSummaryEntry 没有 Online 字段，由调用方处理
		devices = append(devices, entry)
	}

	return devices, nil
}

// IsTokenActive 检查 token 是否仍活跃（遍历所有 session 检查 jti）
func (m *BlacklistManager) IsTokenActive(ctx context.Context, userID int64, jti string) (bool, error) {
	summary, err := m.getUserDevicesSummary(ctx, userID)
	if err != nil {
		return false, err
	}

	for _, entry := range summary {
		session, _ := m.GetDeviceSession(ctx, userID, entry.DeviceType, entry.DeviceID)
		if session != nil {
			if session.AccessJTI == jti || session.RefreshJTI == jti {
				return true, nil
			}
		}
	}
	return false, nil
}

// CleanupExpiredDevices 清理汇总索引中已过期的设备条目
func (m *BlacklistManager) CleanupExpiredDevices(ctx context.Context, userID int64) error {
	summary, err := m.getUserDevicesSummary(ctx, userID)
	if err != nil || len(summary) == 0 {
		return nil
	}

	var changed bool
	var remaining UserDevicesSummary = make(map[string]DeviceSummaryEntry)

	for dtKey, entry := range summary {
		// 检查 session 是否仍存在
		ck := cache.KeyDeviceSession(userID, entry.DeviceType, entry.DeviceID, m.deviceSessionTTL)
		exists, err := m.cache.Exists(ctx, ck.Key)
		if err != nil || !exists {
			changed = true
			continue // session 已过期，从汇总中移除
		}
		remaining[dtKey] = entry
	}

	if changed {
		ck := cache.KeyUserDevices(userID)
		if len(remaining) == 0 {
			_ = m.cache.Delete(ctx, ck.Key)
		} else {
			data, _ := json.Marshal(remaining)
			_ = m.cache.Set(ctx, ck.Key, string(data), ck.TTL)
		}
	}

	return nil
}

// ── 内部辅助方法 ────────────────────────────────────────────────────────────

// getUserDevicesSummary 获取用户设备汇总索引
func (m *BlacklistManager) getUserDevicesSummary(ctx context.Context, userID int64) (UserDevicesSummary, error) {
	ck := cache.KeyUserDevices(userID)
	data, err := m.cache.Get(ctx, ck.Key)
	if err != nil || data == "" {
		return make(UserDevicesSummary), nil
	}

	var summary UserDevicesSummary
	if err := json.Unmarshal([]byte(data), &summary); err != nil {
		return make(UserDevicesSummary), nil
	}
	return summary, nil
}

// updateDevicesSummary 更新汇总索引中指定设备的条目
func (m *BlacklistManager) updateDevicesSummary(ctx context.Context, userID int64, deviceID string, deviceType int8, deviceName string, lastActiveAt int64) error {
	summary, _ := m.getUserDevicesSummary(ctx, userID)

	dtKey := fmt.Sprintf("%d", deviceType)
	summary[dtKey] = DeviceSummaryEntry{
		DeviceID:     deviceID,
		DeviceName:   deviceName,
		DeviceType:   deviceType,
		LastActiveAt: lastActiveAt,
	}

	data, _ := json.Marshal(summary)
	ck := cache.KeyUserDevices(userID)
	return m.cache.Set(ctx, ck.Key, string(data), ck.TTL)
}

// removeFromDevicesSummary 从汇总索引中移除指定设备类型
func (m *BlacklistManager) removeFromDevicesSummary(ctx context.Context, userID int64, deviceType int8) error {
	summary, _ := m.getUserDevicesSummary(ctx, userID)

	dtKey := fmt.Sprintf("%d", deviceType)
	delete(summary, dtKey)

	ck := cache.KeyUserDevices(userID)
	if len(summary) == 0 {
		return m.cache.Delete(ctx, ck.Key)
	}
	data, _ := json.Marshal(summary)
	return m.cache.Set(ctx, ck.Key, string(data), ck.TTL)
}
