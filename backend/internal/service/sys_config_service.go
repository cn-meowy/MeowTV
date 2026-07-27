package service

import (
	"context"
	"encoding/json"
	"log/slog"
	"strconv"
	"strings"
	"sync"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

// SysConfigService 系统配置业务层
type SysConfigService struct {
	repo     repository.SysConfigRepository
	cache    cache.Cache
	mu       sync.RWMutex
	onUpdate map[string]func(context.Context) // 按 ConfigKey 注册的更新回调
}

// NewSysConfigService 创建系统配置 Service
func NewSysConfigService(repo repository.SysConfigRepository, cache cache.Cache) *SysConfigService {
	return &SysConfigService{
		repo:     repo,
		cache:    cache,
		onUpdate: make(map[string]func(context.Context)),
	}
}

// RegisterOnUpdate 注册配置更新回调（按 ConfigKey）
func (s *SysConfigService) RegisterOnUpdate(configKey string, callback func(context.Context)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.onUpdate[configKey] = callback
}

// GetByKey 根据 key 获取配置（优先走缓存）
func (s *SysConfigService) GetByKey(ctx context.Context, key string) (*entity.SysConfig, error) {
	ck := cache.KeySysConfig(key)
	val, err := s.cache.Get(ctx, ck.Key)
	if err == nil && val != "" {
		var cfg entity.SysConfig
		if json.Unmarshal([]byte(val), &cfg) == nil {
			return &cfg, nil
		}
	}

	cfg, err := s.repo.GetByKey(ctx, key)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrNotFound)
	}

	// 写入缓存
	if data, e := json.Marshal(cfg); e == nil {
		_ = s.cache.Set(ctx, ck.Key, string(data), ck.TTL)
	}
	return cfg, nil
}

// ListByGroup 获取指定分组的所有配置（优先走缓存）
func (s *SysConfigService) ListByGroup(ctx context.Context, group string) ([]*entity.SysConfig, error) {
	ck := cache.KeySysConfigGroup(group)
	val, err := s.cache.Get(ctx, ck.Key)
	if err == nil && val != "" {
		var list []*entity.SysConfig
		if json.Unmarshal([]byte(val), &list) == nil {
			return list, nil
		}
	}

	list, err := s.repo.ListByGroup(ctx, group)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	if data, e := json.Marshal(list); e == nil {
		_ = s.cache.Set(ctx, ck.Key, string(data), ck.TTL)
	}
	return list, nil
}

// ListEnabledByGroup 获取指定分组已启用的配置
func (s *SysConfigService) ListEnabledByGroup(ctx context.Context, group string) ([]*entity.SysConfig, error) {
	list, err := s.repo.ListEnabledByGroup(ctx, group)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}
	return list, nil
}

// ListAll 获取所有配置
func (s *SysConfigService) ListAll(ctx context.Context) ([]*entity.SysConfig, error) {
	list, err := s.repo.ListAll(ctx)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}
	return list, nil
}

// Create 创建配置
func (s *SysConfigService) Create(ctx context.Context, req *request.ConfigCreateReq) error {
	cfg := &entity.SysConfig{
		ConfigKey:   req.ConfigKey,
		ConfigGroup: req.ConfigGroup,
		Title:       req.Title,
		Title1:      req.Title1,
		Title2:      req.Title2,
		Title3:      req.Title3,
		Title4:      req.Title4,
		Title5:      req.Title5,
		Title6:      req.Title6,
		Value1:      req.Value1,
		Value2:      req.Value2,
		Value3:      req.Value3,
		Value4:      req.Value4,
		Value5:      req.Value5,
		Value6:      req.Value6,
		SortOrder:   req.SortOrder,
		IsEnabled:   req.IsEnabled,
		Remark:      req.Remark,
	}

	if err := s.repo.Create(ctx, cfg); err != nil {
		if strings.Contains(err.Error(), "UNIQUE") || strings.Contains(err.Error(), "duplicate") {
			return errs.WithMsg("配置项已存在", errs.ErrConflict)
		}
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 清除分组缓存
	s.invalidateGroupCache(ctx, cfg.ConfigGroup)
	return nil
}

// Update 更新配置
func (s *SysConfigService) Update(ctx context.Context, req *request.ConfigUpdateReq) error {
	cfg, err := s.repo.GetByKey(ctx, req.ConfigKey)
	if err != nil {
		return errs.WithMsg("配置项不存在", errs.ErrNotFound)
	}

	// 更新字段
	if req.Title != nil {
		cfg.Title = *req.Title
	}
	if req.Title1 != nil {
		cfg.Title1 = *req.Title1
	}
	if req.Title2 != nil {
		cfg.Title2 = *req.Title2
	}
	if req.Title3 != nil {
		cfg.Title3 = *req.Title3
	}
	if req.Title4 != nil {
		cfg.Title4 = *req.Title4
	}
	if req.Title5 != nil {
		cfg.Title5 = *req.Title5
	}
	if req.Title6 != nil {
		cfg.Title6 = *req.Title6
	}
	if req.Value1 != nil {
		cfg.Value1 = *req.Value1
	}
	if req.Value2 != nil {
		cfg.Value2 = *req.Value2
	}
	if req.Value3 != nil {
		cfg.Value3 = *req.Value3
	}
	if req.Value4 != nil {
		cfg.Value4 = *req.Value4
	}
	if req.Value5 != nil {
		cfg.Value5 = *req.Value5
	}
	if req.Value6 != nil {
		cfg.Value6 = *req.Value6
	}
	if req.SortOrder != nil {
		cfg.SortOrder = *req.SortOrder
	}
	if req.IsEnabled != nil {
		cfg.IsEnabled = *req.IsEnabled
	}
	if req.Remark != nil {
		cfg.Remark = *req.Remark
	}

	if err := s.repo.Update(ctx, cfg); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 清除缓存
	s.invalidateKeyCache(ctx, cfg.ConfigKey)
	s.invalidateGroupCache(ctx, cfg.ConfigGroup)

	// 触发配置变更回调
	s.mu.RLock()
	cb, ok := s.onUpdate[cfg.ConfigKey]
	s.mu.RUnlock()
	if ok {
		cb(ctx)
	}

	return nil
}

// Delete 删除配置
func (s *SysConfigService) Delete(ctx context.Context, id int64) error {
	// 先查出 key 用于清缓存
	list, err := s.repo.ListAll(ctx)
	if err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}
	var cfgKey, cfgGroup string
	for _, c := range list {
		if c.ID == id {
			cfgKey = c.ConfigKey
			cfgGroup = c.ConfigGroup
			break
		}
	}

	if err := s.repo.Delete(ctx, id); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	if cfgKey != "" {
		s.invalidateKeyCache(ctx, cfgKey)
	}
	if cfgGroup != "" {
		s.invalidateGroupCache(ctx, cfgGroup)
	}
	return nil
}

// RefreshCache 强制刷新所有配置缓存
func (s *SysConfigService) RefreshCache(ctx context.Context) error {
	_ = s.cache.DeleteByPattern(ctx, cache.PrefixSysConfig+":*")
	slog.Info("sys_config cache refreshed")
	return nil
}

// invalidateKeyCache 清除单条配置缓存
func (s *SysConfigService) invalidateKeyCache(ctx context.Context, key string) {
	ck := cache.KeySysConfig(key)
	_ = s.cache.Delete(ctx, ck.Key)
}

// invalidateGroupCache 清除分组缓存
func (s *SysConfigService) invalidateGroupCache(ctx context.Context, group string) {
	ck := cache.KeySysConfigGroup(group)
	_ = s.cache.Delete(ctx, ck.Key)
}

// --- 便捷方法：供其他 Service 读取配置 ---

// GetValue 获取指定 key 的配置实体，若不存在返回 nil
func (s *SysConfigService) GetValue(ctx context.Context, key string) *entity.SysConfig {
	cfg, err := s.GetByKey(ctx, key)
	if err != nil {
		return nil
	}
	return cfg
}

// GetBool 判断配置的指定 value 序号是否为 true（"true"/"1"/"yes"）
func (s *SysConfigService) GetBool(ctx context.Context, key string, valueIdx int) bool {
	cfg := s.GetValue(ctx, key)
	if cfg == nil {
		return false
	}
	v := getValueByIndex(cfg, valueIdx)
	return strings.ToLower(v) == "true" || v == "1" || strings.ToLower(v) == "yes"
}

// GetInt 获取配置的指定 value 序号的整数值
func (s *SysConfigService) GetInt(ctx context.Context, key string, valueIdx int) int {
	cfg := s.GetValue(ctx, key)
	if cfg == nil {
		return 0
	}
	v := getValueByIndex(cfg, valueIdx)
	n, _ := strconv.Atoi(v)
	return n
}

// GetString 获取配置的指定 value 序号的字符串值
func (s *SysConfigService) GetString(ctx context.Context, key string, valueIdx int) string {
	cfg := s.GetValue(ctx, key)
	if cfg == nil {
		return ""
	}
	return getValueByIndex(cfg, valueIdx)
}

// GetJSON 获取配置的指定 value 序号的 JSON 值
func (s *SysConfigService) GetJSON(ctx context.Context, key string, valueIdx int, dest interface{}) bool {
	cfg := s.GetValue(ctx, key)
	if cfg == nil {
		return false
	}
	v := getValueByIndex(cfg, valueIdx)
	if v == "" {
		return false
	}
	return json.Unmarshal([]byte(v), dest) == nil
}

// getValueByIndex 根据序号获取 value 字段值（1~6）
func getValueByIndex(cfg *entity.SysConfig, idx int) string {
	switch idx {
	case 1:
		return cfg.Value1
	case 2:
		return cfg.Value2
	case 3:
		return cfg.Value3
	case 4:
		return cfg.Value4
	case 5:
		return cfg.Value5
	case 6:
		return cfg.Value6
	default:
		return ""
	}
}
