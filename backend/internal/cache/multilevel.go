package cache

import (
	"context"
	"fmt"
	"time"
)

// MultiLevelCache implements L1 (local) + L2 (Redis) multi-level caching.
// Read-through: read L1 first, fallback to L2, then populate L1.
// Write-through: write to both L1 and L2.
type MultiLevelCache struct {
	l1          Cache
	l2          *RedisCache
	locker      Locker
	l1TTLFactor float64
	defaultTTL  time.Duration
}

// NewMultiLevelCache creates a new MultiLevelCache.
func NewMultiLevelCache(l1 Cache, l2 *RedisCache, locker Locker, defaultTTL time.Duration) *MultiLevelCache {
	return &MultiLevelCache{
		l1:          l1,
		l2:          l2,
		locker:      locker,
		l1TTLFactor: 0.1, // L1 TTL = 10% of L2 TTL
		defaultTTL:  defaultTTL,
	}
}

// Get implements Cache.Get.
// Read-through: check L1 first, then L2, then populate L1.
func (m *MultiLevelCache) Get(ctx context.Context, key string) (string, error) {
	// Try L1 first
	val, err := m.l1.Get(ctx, key)
	if err == nil {
		return val, nil
	}
	if err != ErrNotFound {
		// L1 error, continue to L2
	}

	// Try L2
	val, err = m.l2.Get(ctx, key)
	if err == nil {
		// Populate L1 with L2 value
		l1TTL := m.calculateL1TTL(m.defaultTTL)
		_ = m.l1.Set(ctx, key, val, l1TTL)
		return val, nil
	}
	if err != ErrNotFound {
		return "", fmt.Errorf("multilevel cache get failed (L2): %w", err)
	}

	return "", ErrNotFound
}

// Set implements Cache.Set.
// Write-through: write to both L2 and L1.
func (m *MultiLevelCache) Set(ctx context.Context, key string, value string, ttl time.Duration) error {
	if ttl == 0 {
		ttl = m.defaultTTL
	}

	// Write to L2 first (source of truth)
	if err := m.l2.Set(ctx, key, value, ttl); err != nil {
		return fmt.Errorf("multilevel cache set failed (L2): %w", err)
	}

	// Write to L1
	l1TTL := m.calculateL1TTL(ttl)
	if err := m.l1.Set(ctx, key, value, l1TTL); err != nil {
		// L1 write failure is non-fatal, L2 is the source of truth
		// log warning here if needed
	}

	return nil
}

// Delete implements Cache.Delete.
// Delete from both L1 and L2.
func (m *MultiLevelCache) Delete(ctx context.Context, key string) error {
	// Delete from both layers
	if err := m.l2.Delete(ctx, key); err != nil {
		return fmt.Errorf("multilevel cache delete failed (L2): %w", err)
	}
	if err := m.l1.Delete(ctx, key); err != nil {
		// L1 delete failure is non-fatal
	}
	return nil
}

// MGet implements Cache.MGet.
func (m *MultiLevelCache) MGet(ctx context.Context, keys ...string) ([]string, error) {
	// Try L1 first
	l1Results, _ := m.l1.MGet(ctx, keys...)
	l1Misses := make([]string, 0)
	missingIndices := make([]int, 0)

	for i, val := range l1Results {
		if val == "" {
			l1Misses = append(l1Misses, keys[i])
			missingIndices = append(missingIndices, i)
		}
	}

	if len(l1Misses) == 0 {
		return l1Results, nil
	}

	// Fetch misses from L2
	l2Results, err := m.l2.MGet(ctx, l1Misses...)
	if err != nil {
		return nil, fmt.Errorf("multilevel cache mget failed (L2): %w", err)
	}

	// Populate L1 and merge results
	l1TTL := m.calculateL1TTL(m.defaultTTL)
	backfill := make(map[string]string)
	for i, idx := range missingIndices {
		val := l2Results[i]
		l1Results[idx] = val
		if val != "" {
			backfill[keys[idx]] = val
		}
	}

	if len(backfill) > 0 {
		_ = m.l1.MSet(ctx, backfill, l1TTL)
	}

	return l1Results, nil
}

// MSet implements Cache.MSet.
func (m *MultiLevelCache) MSet(ctx context.Context, pairs map[string]string, ttl time.Duration) error {
	if ttl == 0 {
		ttl = m.defaultTTL
	}

	// Write to L2 first
	if err := m.l2.MSet(ctx, pairs, ttl); err != nil {
		return fmt.Errorf("multilevel cache mset failed (L2): %w", err)
	}

	// Write to L1
	l1TTL := m.calculateL1TTL(ttl)
	if err := m.l1.MSet(ctx, pairs, l1TTL); err != nil {
		// L1 write failure is non-fatal
	}

	return nil
}

// Exists implements Cache.Exists.
func (m *MultiLevelCache) Exists(ctx context.Context, key string) (bool, error) {
	// Check L1 first
	exists, err := m.l1.Exists(ctx, key)
	if err == nil && exists {
		return true, nil
	}

	// Check L2
	return m.l2.Exists(ctx, key)
}

// Expire implements Cache.Expire.
func (m *MultiLevelCache) Expire(ctx context.Context, key string, ttl time.Duration) error {
	// Expire in L2 (L1 will be stale and eventually evicted)
	return m.l2.Expire(ctx, key, ttl)
}

// Incr implements Cache.Incr.
func (m *MultiLevelCache) Incr(ctx context.Context, key string) (int64, error) {
	// Increment in L2 (source of truth)
	result, err := m.l2.Incr(ctx, key)
	if err != nil {
		return 0, fmt.Errorf("multilevel cache incr failed (L2): %w", err)
	}
	// Delete from L1 to ensure consistency
	_ = m.l1.Delete(ctx, key)
	return result, nil
}

// IncrBy implements Cache.IncrBy.
func (m *MultiLevelCache) IncrBy(ctx context.Context, key string, delta int64) (int64, error) {
	result, err := m.l2.IncrBy(ctx, key, delta)
	if err != nil {
		return 0, fmt.Errorf("multilevel cache incrby failed (L2): %w", err)
	}
	_ = m.l1.Delete(ctx, key)
	return result, nil
}

// Decr implements Cache.Decr.
func (m *MultiLevelCache) Decr(ctx context.Context, key string) (int64, error) {
	result, err := m.l2.Decr(ctx, key)
	if err != nil {
		return 0, fmt.Errorf("multilevel cache decr failed (L2): %w", err)
	}
	_ = m.l1.Delete(ctx, key)
	return result, nil
}

// DeleteByPattern implements Cache.DeleteByPattern.
// Deletes from L2 (L1 pattern deletion is not supported by most local caches).
func (m *MultiLevelCache) DeleteByPattern(ctx context.Context, pattern string) error {
	if err := m.l2.DeleteByPattern(ctx, pattern); err != nil {
		return fmt.Errorf("multilevel cache deletebypattern failed (L2): %w", err)
	}
	// L1 does not support pattern deletion, L1 entries will expire naturally
	return nil
}

// Close implements Cache.Close.
func (m *MultiLevelCache) Close() error {
	if err := m.l2.Close(); err != nil {
		return fmt.Errorf("multilevel cache close failed (L2): %w", err)
	}
	if err := m.l1.Close(); err != nil {
		return fmt.Errorf("multilevel cache close failed (L1): %w", err)
	}
	return nil
}

// calculateL1TTL returns the TTL for L1 based on L2 TTL.
func (m *MultiLevelCache) calculateL1TTL(l2TTL time.Duration) time.Duration {
	l1TTL := time.Duration(float64(l2TTL) * m.l1TTLFactor)
	if l1TTL < time.Second {
		l1TTL = time.Second // minimum 1 second
	}
	return l1TTL
}

// compile-time check that MultiLevelCache implements Cache
var _ Cache = (*MultiLevelCache)(nil)
