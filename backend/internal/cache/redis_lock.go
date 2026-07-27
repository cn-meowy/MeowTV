package cache

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

const (
	// DefaultLockTTL is the default TTL for distributed locks.
	DefaultLockTTL = 30 * time.Second
	// LockRetryInterval is the interval between lock acquisition retries.
	LockRetryInterval = 50 * time.Millisecond
)

// ErrLockNotAcquired is returned when TryLock fails to acquire the lock.
var ErrLockNotAcquired = errors.New("lock: not acquired")

// RedisLocker is a distributed locker implementation using Redis.
type RedisLocker struct {
	client *redis.Client
}

// NewRedisLocker creates a new RedisLocker.
func NewRedisLocker(client *redis.Client) *RedisLocker {
	return &RedisLocker{client: client}
}

// Lock implements Locker.Lock.
// Blocks until the lock is acquired or the context is cancelled.
func (l *RedisLocker) Lock(ctx context.Context, key string, ttl time.Duration) (Lock, error) {
	if ttl == 0 {
		ttl = DefaultLockTTL
	}
	value := uuid.New().String()

	for {
		acquired, err := l.tryAcquire(ctx, key, value, ttl)
		if err != nil {
			return nil, err
		}
		if acquired {
			return &redisLock{
				client: l.client,
				key:    key,
				value:  value,
			}, nil
		}

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(LockRetryInterval):
			// continue retrying
		}
	}
}

// TryLock implements Locker.TryLock.
// Returns an error if the lock is already held.
func (l *RedisLocker) TryLock(ctx context.Context, key string, ttl time.Duration) (Lock, error) {
	if ttl == 0 {
		ttl = DefaultLockTTL
	}
	value := uuid.New().String()

	acquired, err := l.tryAcquire(ctx, key, value, ttl)
	if err != nil {
		return nil, err
	}
	if !acquired {
		return nil, ErrLockNotAcquired
	}
	return &redisLock{
		client: l.client,
		key:    key,
		value:  value,
	}, nil
}

// tryAcquire attempts to acquire the lock using SET NX EX.
func (l *RedisLocker) tryAcquire(ctx context.Context, key, value string, ttl time.Duration) (bool, error) {
	result, err := l.client.SetNX(ctx, key, value, ttl).Result()
	if err != nil {
		return false, err
	}
	return result, nil
}

// redisLock represents an acquired Redis-based lock.
type redisLock struct {
	client *redis.Client
	key    string
	value  string
}

// Unlock implements Lock.Unlock.
// Uses a Lua script to ensure atomicity: only deletes if value matches.
var unlockScript = redis.NewScript(`
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("del", KEYS[1])
else
    return 0
end
`)

// Unlock implements Lock.Unlock.
func (l *redisLock) Unlock(ctx context.Context) error {
	_, err := unlockScript.Run(ctx, l.client, []string{l.key}, l.value).Result()
	return err
}

// Renew implements Lock.Renew.
// Uses a Lua script to ensure atomicity: only extends TTL if value matches.
var renewScript = redis.NewScript(`
if redis.call("get", KEYS[1]) == ARGV[1] then
    return redis.call("expire", KEYS[1], ARGV[2])
else
    return 0
end
`)

// Renew implements Lock.Renew.
func (l *redisLock) Renew(ctx context.Context, ttl time.Duration) error {
	result, err := renewScript.Run(ctx, l.client, []string{l.key}, l.value, int(ttl.Seconds())).Int64()
	if err != nil {
		return err
	}
	if result == 0 {
		return errors.New("lock: renew failed, lock value mismatch or expired")
	}
	return nil
}

// compile-time check that RedisLocker implements Locker
var _ Locker = (*RedisLocker)(nil)
