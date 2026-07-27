package cache

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"cn.meow/meowtv/internal/config"
	"github.com/dgraph-io/ristretto/v2"
)

// RistrettoCache is a cache implementation using dgraph-io/ristretto.
type RistrettoCache struct {
	cache      *ristretto.Cache[string, string]
	defaultTTL time.Duration
}

// NewRistrettoCache creates a new RistrettoCache instance.
func NewRistrettoCache(cfg config.RistrettoConfig) (*RistrettoCache, error) {
	maxCost := cfg.MaxCost
	if maxCost == 0 {
		maxCost = 100 * 1024 * 1024 // 100MB default
	}
	bufferItems := cfg.BufferItems
	if bufferItems == 0 {
		bufferItems = 64
	}
	defaultTTL := cfg.DefaultTTL
	if defaultTTL == 0 {
		defaultTTL = 30 * time.Minute
	}

	cache, err := ristretto.NewCache[string, string](&ristretto.Config[string, string]{
		MaxCost:     maxCost,
		BufferItems: bufferItems,
		NumCounters: maxCost / 10,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create ristretto cache: %w", err)
	}

	return &RistrettoCache{
		cache:      cache,
		defaultTTL: defaultTTL,
	}, nil
}

// Get implements Cache.Get.
func (c *RistrettoCache) Get(ctx context.Context, key string) (string, error) {
	val, found := c.cache.Get(key)
	if !found {
		return "", ErrNotFound
	}
	return val, nil
}

// Set implements Cache.Set.
func (c *RistrettoCache) Set(ctx context.Context, key string, value string, ttl time.Duration) error {
	if ttl == 0 {
		ttl = c.defaultTTL
	}
	// Ristretto uses cost-based eviction, we approximate cost as len(value)
	cost := int64(len(value))
	// Ristretto v2 uses SetWithTTL for TTL support
	if !c.cache.SetWithTTL(key, value, cost, ttl) {
		return fmt.Errorf("failed to set cache key %s", key)
	}
	// Ristretto Set is async, wait for it to be visible
	c.cache.Wait()
	return nil
}

// Delete implements Cache.Delete.
func (c *RistrettoCache) Delete(ctx context.Context, key string) error {
	c.cache.Del(key)
	return nil
}

// MGet implements Cache.MGet.
func (c *RistrettoCache) MGet(ctx context.Context, keys ...string) ([]string, error) {
	results := make([]string, len(keys))
	for i, key := range keys {
		val, found := c.cache.Get(key)
		if !found {
			results[i] = ""
			continue
		}
		results[i] = val
	}
	return results, nil
}

// MSet implements Cache.MSet.
func (c *RistrettoCache) MSet(ctx context.Context, pairs map[string]string, ttl time.Duration) error {
	if ttl == 0 {
		ttl = c.defaultTTL
	}
	for key, value := range pairs {
		cost := int64(len(value))
		c.cache.SetWithTTL(key, value, cost, ttl)
	}
	c.cache.Wait()
	return nil
}

// Exists implements Cache.Exists.
func (c *RistrettoCache) Exists(ctx context.Context, key string) (bool, error) {
	_, found := c.cache.Get(key)
	return found, nil
}

// Expire implements Cache.Expire.
// Note: Ristretto does not support per-item TTL modification after insertion.
// This is a no-op for Ristretto but maintained for interface compatibility.
func (c *RistrettoCache) Expire(ctx context.Context, key string, ttl time.Duration) error {
	// Ristretto does not support TTL modification
	return nil
}

// Incr implements Cache.Incr.
func (c *RistrettoCache) Incr(ctx context.Context, key string) (int64, error) {
	return c.incrBy(key, 1)
}

// IncrBy implements Cache.IncrBy.
func (c *RistrettoCache) IncrBy(ctx context.Context, key string, delta int64) (int64, error) {
	return c.incrBy(key, delta)
}

func (c *RistrettoCache) incrBy(key string, delta int64) (int64, error) {
	val, found := c.cache.Get(key)
	if !found {
		newVal := delta
		c.cache.Set(key, strconv.FormatInt(newVal, 10), newVal)
		c.cache.Wait()
		return newVal, nil
	}
	oldVal, err := strconv.ParseInt(val, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("failed to parse cache value as int64: %w", err)
	}
	newVal := oldVal + delta
	c.cache.Set(key, strconv.FormatInt(newVal, 10), newVal)
	c.cache.Wait()
	return newVal, nil
}

// Decr implements Cache.Decr.
func (c *RistrettoCache) Decr(ctx context.Context, key string) (int64, error) {
	return c.incrBy(key, -1)
}

// DeleteByPattern implements Cache.DeleteByPattern.
// Note: Ristretto does not expose keys, so this is a no-op.
func (c *RistrettoCache) DeleteByPattern(ctx context.Context, pattern string) error {
	// Ristretto does not expose keys, cannot delete by pattern efficiently
	return nil
}

// Close implements Cache.Close.
func (c *RistrettoCache) Close() error {
	c.cache.Close()
	return nil
}
