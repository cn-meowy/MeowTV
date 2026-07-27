package middleware

import (
	"fmt"
	"log/slog"
	"net/http"
	"runtime/debug"

	"github.com/labstack/echo/v4"
)

// Recovery returns a middleware that recovers from panics.
func Recovery() echo.MiddlewareFunc {
	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			defer func() {
				if r := recover(); r != nil {
					stack := debug.Stack()
					slog.Error("panic recovered",
						"panic", fmt.Sprintf("%v", r),
						"stack", string(stack),
						"request_id", c.Response().Header().Get(echo.HeaderXRequestID),
					)
					c.Error(echo.NewHTTPError(http.StatusInternalServerError, "内部服务错误"))
				}
			}()
			return next(c)
		}
	}
}
