package cache

import (
	"context"
	"fmt"
	"time"
)

// ErrNotFound is returned when a cache key does not exist.
var ErrNotFound = fmt.Errorf("cache: key not found")

// Cache defines the interface for caching operations.
// All implementations must be thread-safe.
type Cache interface {
	// Get retrieves the value for a given key.
	// Returns empty string with nil error if key does not exist.
	Get(ctx context.Context, key string) (string, error)

	// Set stores a key-value pair with the specified TTL.
	// TTL of 0 means no expiration.
	Set(ctx context.Context, key string, value string, ttl time.Duration) error

	// Delete removes a key.
	Delete(ctx context.Context, key string) error

	// MGet retrieves values for multiple keys.
	// Returns empty string for non-existent keys.
	MGet(ctx context.Context, keys ...string) ([]string, error)

	// MSet stores multiple key-value pairs with the specified TTL.
	MSet(ctx context.Context, pairs map[string]string, ttl time.Duration) error

	// Exists checks whether a key exists.
	Exists(ctx context.Context, key string) (bool, error)

	// Expire sets a TTL on an existing key.
	Expire(ctx context.Context, key string, ttl time.Duration) error

	// Incr increments the counter at the given key and returns the new value.
	// Creates the key with value "1" if it does not exist.
	Incr(ctx context.Context, key string) (int64, error)

	// IncrBy increments the counter at the given key by the specified delta and returns the new value.
	// Creates the key with value equal to delta if it does not exist.
	IncrBy(ctx context.Context, key string, delta int64) (int64, error)

	// Decr decrements the counter at the given key and returns the new value.
	// Creates the key with value "-1" if it does not exist.
	Decr(ctx context.Context, key string) (int64, error)

	// DeleteByPattern removes all keys matching the given glob pattern.
	// Pattern examples: "user:*", "video:list:*"
	DeleteByPattern(ctx context.Context, pattern string) error

	// Close releases all resources held by the cache.
	Close() error
}
