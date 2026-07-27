package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/labstack/echo/v4"
)

// RateLimitConfig holds rate limiting configuration.
type RateLimitConfig struct {
	// Requests per window
	Max int
	// Window duration
	Window time.Duration
}

const (
	defaultMaxRequests = 100
	defaultWindow      = 1 * time.Minute
)

// RateLimit returns a middleware that implements a sliding window rate limiter.
// For production, consider using Redis-based rate limiting for distributed deployments.
func RateLimit() echo.MiddlewareFunc {
	return RateLimitWithConfig(RateLimitConfig{
		Max:    defaultMaxRequests,
		Window: defaultWindow,
	})
}

// RateLimitWithConfig returns a sliding window rate limiting middleware with custom configuration.
func RateLimitWithConfig(cfg RateLimitConfig) echo.MiddlewareFunc {
	if cfg.Max <= 0 {
		cfg.Max = defaultMaxRequests
	}
	if cfg.Window <= 0 {
		cfg.Window = defaultWindow
	}

	limiter := newSlidingWindowLimiter(cfg.Max, cfg.Window)

	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			identifier := c.RealIP()
			if identifier == "" {
				identifier = "unknown"
			}

			if limiter.allow(identifier) {
				return next(c)
			}

			return c.JSON(http.StatusTooManyRequests, map[string]interface{}{
				"code": 429,
				"msg":  "请求过于频繁",
			})
		}
	}
}

// slidingWindowLimiter implements a sliding window rate limiter.
// Unlike fixed window, this tracks individual request timestamps within the window
// to prevent the boundary burst problem where 2x requests can pass at window boundaries.
type slidingWindowLimiter struct {
	max      time.Duration
	window   time.Duration
	mu       sync.RWMutex
	visitors map[string]*swVisitor
}

type swVisitor struct {
	timestamps []time.Time
}

func newSlidingWindowLimiter(max int, window time.Duration) *slidingWindowLimiter {
	rl := &slidingWindowLimiter{
		max:      time.Duration(max),
		window:   window,
		visitors: make(map[string]*swVisitor),
	}

	// Start cleanup goroutine
	go rl.cleanup()

	return rl
}

func (rl *slidingWindowLimiter) allow(identifier string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	windowStart := now.Add(-rl.window)

	v, exists := rl.visitors[identifier]
	if !exists {
		v = &swVisitor{
			timestamps: []time.Time{now},
		}
		rl.visitors[identifier] = v
		return true
	}

	// Filter out timestamps outside the sliding window
	validIdx := 0
	for i, ts := range v.timestamps {
		if ts.After(windowStart) {
			validIdx = i
			break
		}
		if i == len(v.timestamps)-1 {
			// All timestamps are outside the window
			validIdx = len(v.timestamps)
		}
	}
	v.timestamps = v.timestamps[validIdx:]

	// Check if under limit
	if time.Duration(len(v.timestamps)) < rl.max {
		v.timestamps = append(v.timestamps, now)
		return true
	}

	return false
}

func (rl *slidingWindowLimiter) cleanup() {
	ticker := time.NewTicker(rl.window)
	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		windowStart := now.Add(-rl.window)
		for key, v := range rl.visitors {
			validIdx := 0
			for i, ts := range v.timestamps {
				if ts.After(windowStart) {
					validIdx = i
					break
				}
				if i == len(v.timestamps)-1 {
					validIdx = len(v.timestamps)
				}
			}
			v.timestamps = v.timestamps[validIdx:]
			if len(v.timestamps) == 0 {
				delete(rl.visitors, key)
			}
		}
		rl.mu.Unlock()
	}
}
