package middleware

import (
	"net/http"
	"strings"

	"github.com/labstack/echo/v4"
)

// CORSConfig holds CORS middleware configuration.
type CORSConfig struct {
	// AllowedOrigins is the list of allowed origins.
	// If empty, all origins are allowed (equivalent to "*") — use only in dev.
	// For production, specify explicit origins like ["https://meowtv.example.com"].
	AllowedOrigins []string
}

// CORS returns a middleware that handles Cross-Origin Resource Sharing.
// If allowedOrigins is empty, all origins are allowed (for backward compatibility in dev).
// For production, only the specified origins are allowed.
func CORS(cfg CORSConfig) echo.MiddlewareFunc {
	// Build a set for fast lookup
	originSet := make(map[string]bool, len(cfg.AllowedOrigins))
	for _, o := range cfg.AllowedOrigins {
		originSet[strings.TrimSpace(o)] = true
	}
	allowAll := len(originSet) == 0

	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			origin := c.Request().Header.Get("Origin")

			if allowAll {
				c.Response().Header().Set("Access-Control-Allow-Origin", "*")
			} else if origin != "" && originSet[origin] {
				c.Response().Header().Set("Access-Control-Allow-Origin", origin)
				c.Response().Header().Set("Vary", "Origin")
			} else {
				// Origin not allowed — for preflight, reject; for actual request, continue without CORS headers
				if c.Request().Method == http.MethodOptions {
					return c.NoContent(http.StatusForbidden)
				}
				return next(c)
			}

			c.Response().Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			c.Response().Header().Set("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization, X-Request-ID")
			c.Response().Header().Set("Access-Control-Expose-Headers", "X-Request-ID")
			c.Response().Header().Set("Access-Control-Max-Age", "86400")
			c.Response().Header().Set("Access-Control-Allow-Credentials", "true")

			if c.Request().Method == http.MethodOptions {
				return c.NoContent(http.StatusNoContent)
			}

			return next(c)
		}
	}
}
