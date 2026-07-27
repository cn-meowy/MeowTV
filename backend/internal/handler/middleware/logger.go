package middleware

import (
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
)

const (
	// RequestIDHeader is the header name for request ID.
	RequestIDHeader = echo.HeaderXRequestID
	// RequestIDKey is the context key for request ID.
	RequestIDKey = "request_id"
)

// Logger returns a middleware that logs HTTP requests with slog.
func Logger() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			start := time.Now()

			// Generate request ID
			requestID := c.Request().Header.Get(RequestIDHeader)
			if requestID == "" {
				requestID = uuid.NewString()
			}
			c.Response().Header().Set(RequestIDHeader, requestID)
			c.Set(RequestIDKey, requestID)

			// Process request
			err := next(c)

			// Log request
			latency := time.Since(start)
			status := c.Response().Status
			slog.Info("request completed",
				"request_id", requestID,
				"method", c.Request().Method,
				"path", c.Request().URL.Path,
				"status", status,
				"latency_ms", latency.Milliseconds(),
				"ip", c.RealIP(),
				"user_agent", c.Request().UserAgent(),
			)

			return err
		}
	}
}

// GetRequestID extracts the request ID from the Echo context.
func GetRequestID(c echo.Context) string {
	if id, ok := c.Get(RequestIDKey).(string); ok {
		return id
	}
	return ""
}
