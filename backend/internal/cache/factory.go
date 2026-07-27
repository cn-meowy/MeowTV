package cache

import (
	"fmt"

	"cn.meow/meowtv/internal/config"
)

// CacheProvider holds both the Cache and Locker instances.
type CacheProvider struct {
	Cache  Cache
	Locker Locker
}

// NewCacheProvider creates a CacheProvider based on the cache configuration.
// Returns an error if the cache type is unsupported.
func NewCacheProvider(cfg *config.CacheConfig) (*CacheProvider, error) {
	switch cfg.Type {
	case "gocache":
		lc := NewGoCache(cfg.Local)
		return &CacheProvider{
			Cache:  lc,
			Locker: NewLocalLocker(),
		}, nil

	case "ristretto":
		rc, err := NewRistrettoCache(cfg.Ristretto)
		if err != nil {
			return nil, fmt.Errorf("failed to create ristretto cache: %w", err)
		}
		return &CacheProvider{
			Cache:  rc,
			Locker: NewLocalLocker(),
		}, nil

	case "redis":
		rc, err := NewRedisCache(cfg.Redis)
		if err != nil {
			return nil, fmt.Errorf("failed to create redis cache: %w", err)
		}
		rl := NewRedisLocker(rc.Client())
		return &CacheProvider{
			Cache:  rc,
			Locker: rl,
		}, nil

	case "multilevel":
		// Create L1 (GoCache or RistrettoCache based on config)
		var l1 Cache
		if cfg.MultiLevel.Local.DefaultTTL != 0 {
			// Use Ristretto if RistrettoConfig has non-zero MaxCost
			if cfg.Ristretto.MaxCost != 0 {
				rc, err := NewRistrettoCache(cfg.Ristretto)
				if err != nil {
					return nil, fmt.Errorf("failed to create ristretto cache for multilevel L1: %w", err)
				}
				l1 = rc
			} else {
				l1 = NewGoCache(cfg.MultiLevel.Local)
			}
		} else {
			l1 = NewGoCache(cfg.Local)
		}

		// Create L2 (Redis)
		l2, err := NewRedisCache(cfg.MultiLevel.Redis)
		if err != nil {
			return nil, fmt.Errorf("failed to create redis cache for multilevel L2: %w", err)
		}

		// Create locker
		locker := NewRedisLocker(l2.Client())

		// Create multilevel cache
		mlc := NewMultiLevelCache(l1, l2, locker, cfg.MultiLevel.Local.DefaultTTL)

		return &CacheProvider{
			Cache:  mlc,
			Locker: locker,
		}, nil

	default:
		return nil, fmt.Errorf("unsupported cache type: %s (supported: gocache, ristretto, redis, multilevel)", cfg.Type)
	}
}
