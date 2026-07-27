package cache

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"cn.meow/meowtv/internal/config"
)

// RedisCache is a cache implementation using go-redis.
type RedisCache struct {
	client *redis.Client
}

// NewRedisCache creates a new RedisCache instance.
func NewRedisCache(cfg config.RedisConfig) (*RedisCache, error) {
	password, err := cfg.Password.Plain()
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt redis password: %w", err)
	}

	client := redis.NewClient(&redis.Options{
		Addr:     cfg.Addr,
		Password: password,
		DB:       cfg.DB,
	})

	// Verify connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis connection failed: %w", err)
	}

	return &RedisCache{client: client}, nil
}

// Get implements Cache.Get.
func (c *RedisCache) Get(ctx context.Context, key string) (string, error) {
	val, err := c.client.Get(ctx, key).Result()
	if err == redis.Nil {
		return "", ErrNotFound
	}
	if err != nil {
		return "", fmt.Errorf("redis get failed: %w", err)
	}
	return val, nil
}

// Set implements Cache.Set.
func (c *RedisCache) Set(ctx context.Context, key string, value string, ttl time.Duration) error {
	var err error
	if ttl == 0 {
		err = c.client.Set(ctx, key, value, 0).Err()
	} else {
		err = c.client.Set(ctx, key, value, ttl).Err()
	}
	if err != nil {
		return fmt.Errorf("redis set failed: %w", err)
	}
	return nil
}

// Delete implements Cache.Delete.
func (c *RedisCache) Delete(ctx context.Context, key string) error {
	err := c.client.Del(ctx, key).Err()
	if err != nil {
		return fmt.Errorf("redis del failed: %w", err)
	}
	return nil
}

// MGet implements Cache.MGet.
func (c *RedisCache) MGet(ctx context.Context, keys ...string) ([]string, error) {
	if len(keys) == 0 {
		return []string{}, nil
	}
	vals, err := c.client.MGet(ctx, keys...).Result()
	if err != nil {
		return nil, fmt.Errorf("redis mget failed: %w", err)
	}
	results := make([]string, len(keys))
	for i, val := range vals {
		if val == nil {
			results[i] = ""
		} else {
			results[i] = val.(string)
		}
	}
	return results, nil
}

// MSet implements Cache.MSet.
func (c *RedisCache) MSet(ctx context.Context, pairs map[string]string, ttl time.Duration) error {
	if len(pairs) == 0 {
		return nil
	}
	pipe := c.client.Pipeline()
	for key, value := range pairs {
		if ttl == 0 {
			pipe.Set(ctx, key, value, 0)
		} else {
			pipe.Set(ctx, key, value, ttl)
		}
	}
	_, err := pipe.Exec(ctx)
	if err != nil {
		return fmt.Errorf("redis mset failed: %w", err)
	}
	return nil
}

// Exists implements Cache.Exists.
func (c *RedisCache) Exists(ctx context.Context, key string) (bool, error) {
	count, err := c.client.Exists(ctx, key).Result()
	if err != nil {
		return false, fmt.Errorf("redis exists failed: %w", err)
	}
	return count > 0, nil
}

// Expire implements Cache.Expire.
func (c *RedisCache) Expire(ctx context.Context, key string, ttl time.Duration) error {
	err := c.client.Expire(ctx, key, ttl).Err()
	if err != nil {
		return fmt.Errorf("redis expire failed: %w", err)
	}
	return nil
}

// Incr implements Cache.Incr.
func (c *RedisCache) Incr(ctx context.Context, key string) (int64, error) {
	return c.client.Incr(ctx, key).Result()
}

// IncrBy implements Cache.IncrBy.
func (c *RedisCache) IncrBy(ctx context.Context, key string, delta int64) (int64, error) {
	return c.client.IncrBy(ctx, key, delta).Result()
}

// Decr implements Cache.Decr.
func (c *RedisCache) Decr(ctx context.Context, key string) (int64, error) {
	return c.client.Decr(ctx, key).Result()
}

// DeleteByPattern implements Cache.DeleteByPattern.
// Uses SCAN + DEL pipeline to avoid blocking KEYS command.
func (c *RedisCache) DeleteByPattern(ctx context.Context, pattern string) error {
	var cursor uint64
	var err error
	for {
		var keys []string
		keys, cursor, err = c.client.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			return fmt.Errorf("redis scan failed: %w", err)
		}
		if len(keys) > 0 {
			err = c.client.Del(ctx, keys...).Err()
			if err != nil {
				return fmt.Errorf("redis del failed: %w", err)
			}
		}
		if cursor == 0 {
			break
		}
	}
	return nil
}

// Close implements Cache.Close.
func (c *RedisCache) Close() error {
	return c.client.Close()
}

// Client returns the underlying redis.Client for use by RedisLocker.
func (c *RedisCache) Client() *redis.Client {
	return c.client
}

// compile-time check that RedisCache implements Cache
var _ Cache = (*RedisCache)(nil)

// patternToRegex converts a glob pattern to a regex pattern.
// Supports: * matches any sequence of characters.
func patternToRegex(pattern string) string {
	// Escape special regex characters except *
	escaped := strings.ReplaceAll(pattern, ".", "\\.")
	// Replace * with .*
	return "^" + strings.ReplaceAll(escaped, "*", ".*") + "$"
}
