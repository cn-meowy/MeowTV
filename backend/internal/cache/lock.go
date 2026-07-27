package cache

import (
	"context"
	"time"
)

// Locker defines the interface for distributed locking.
type Locker interface {
	// Lock blocks until the lock is acquired or the context is cancelled.
	Lock(ctx context.Context, key string, ttl time.Duration) (Lock, error)

	// TryLock attempts to acquire the lock without blocking.
	// Returns an error if the lock is already held.
	TryLock(ctx context.Context, key string, ttl time.Duration) (Lock, error)
}

// Lock represents an acquired lock.
// Always release the lock when done, preferably using defer.
type Lock interface {
	// Unlock releases the lock.
	Unlock(ctx context.Context) error

	// Renew extends the lock TTL.
	Renew(ctx context.Context, ttl time.Duration) error
}
