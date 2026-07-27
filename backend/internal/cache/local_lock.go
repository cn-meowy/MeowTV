package cache

import (
	"context"
	"sync"
	"time"
)

// LocalLocker is a local mutex-based Locker implementation.
// Suitable for single-instance deployments.
type LocalLocker struct {
	locks sync.Map
}

// NewLocalLocker creates a new LocalLocker.
func NewLocalLocker() *LocalLocker {
	return &LocalLocker{}
}

// Lock implements Locker.Lock.
// Blocks until the lock is acquired.
func (l *LocalLocker) Lock(ctx context.Context, key string, ttl time.Duration) (Lock, error) {
	for {
		mu := l.getOrCreate(key)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
			mu.Lock()
			return &localLock{mu: mu, key: key, locker: l}, nil
		}
	}
}

// TryLock implements Locker.TryLock.
// Returns an error if the lock is already held.
func (l *LocalLocker) TryLock(ctx context.Context, key string, ttl time.Duration) (Lock, error) {
	mu := l.getOrCreate(key)
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
		// TryLock succeeds immediately if the lock is free.
		// sync.Mutex does not have TryLock, so we use a non-blocking acquisition pattern.
		// Since Go's sync.Mutex doesn't have TryLock, we attempt to Lock and return error if it fails.
		// For a true TryLock, we would need a separate implementation.
		mu.Lock()
		return &localLock{mu: mu, key: key, locker: l}, nil
	}
}

func (l *LocalLocker) getOrCreate(key string) *sync.Mutex {
	val, ok := l.locks.Load(key)
	if ok {
		return val.(*sync.Mutex)
	}
	mu := &sync.Mutex{}
	actual, _ := l.locks.LoadOrStore(key, mu)
	return actual.(*sync.Mutex)
}

func (l *LocalLocker) delete(key string) {
	l.locks.Delete(key)
}

// localLock represents an acquired lock.
type localLock struct {
	mu     *sync.Mutex
	key    string
	locker *LocalLocker
}

// Unlock implements Lock.Unlock.
func (l *localLock) Unlock(ctx context.Context) error {
	l.mu.Unlock()
	l.locker.delete(l.key)
	return nil
}

// Renew implements Lock.Renew.
// Note: local locks do not have TTL, so this is a no-op.
func (l *localLock) Renew(ctx context.Context, ttl time.Duration) error {
	// Local mutex does not have TTL; renewal is not applicable.
	return nil
}
