package wire

import (
	"time"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/config"
)

// ProvideCache 从 CacheProvider 提取 cache.Cache 接口
func ProvideCache(p *cache.CacheProvider) cache.Cache {
	return p.Cache
}

// ProvideAuthConfig 从 Config 提取 AuthConfig
func ProvideAuthConfig(cfg *config.Config) *config.AuthConfig {
	return &cfg.Auth
}

// ProvideDeviceSessionTTL 从 AuthConfig 提取设备会话 TTL
func ProvideDeviceSessionTTL(cfg *config.AuthConfig) time.Duration {
	if cfg.DeviceSessionTTL <= 0 {
		return cache.TTLDeviceSession
	}
	return cfg.DeviceSessionTTL
}

// ProvideDBConfig 从 Config 提取 DBConfig
func ProvideDBConfig(cfg *config.Config) *config.DBConfig {
	return &cfg.DB
}

// ProvideCacheConfig 从 Config 提取 CacheConfig
func ProvideCacheConfig(cfg *config.Config) *config.CacheConfig {
	return &cfg.Cache
}

// ProvideAppConfig 从 Config 提取 AppConfig
func ProvideAppConfig(cfg *config.Config) *config.AppConfig {
	return &cfg.App
}

// ProvideDemoLocalDataDir 从 Config 提取 demo 模式的本地数据目录路径
func ProvideDemoLocalDataDir(cfg *config.Config) string {
	return cfg.Demo.LocalDataDir
}
