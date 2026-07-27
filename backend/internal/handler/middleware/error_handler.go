package middleware

import (
	"log/slog"
	"net/http"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/response"
)

// ErrorHandler returns a custom HTTP error handler for Echo.
// It converts all errors to the unified response format.
func ErrorHandler() echo.HTTPErrorHandler {
	return func(err error, c echo.Context) {
		code := http.StatusInternalServerError
		msg := "内部服务错误"

		// Handle AppError
		if appErr := errs.AsAppError(err); appErr != nil {
			code = appErr.Code
			msg = appErr.Msg
			if code >= 500 {
				slog.Error("internal server error",
					"code", code,
					"msg", msg,
					"inner", appErr.Inner,
					"request_id", GetRequestID(c),
				)
			} else {
				slog.Debug("request error",
					"code", code,
					"msg", msg,
					"error", err.Error(),
					"request_id", GetRequestID(c),
				)
			}
			response.JSON(c, code, msg, nil)
			return
		}

		// Handle Echo HTTPError
		if he, ok := err.(*echo.HTTPError); ok {
			code = he.Code
			if m, ok := he.Message.(string); ok {
				msg = m
			}
			response.JSON(c, code, msg, nil)
			return
		}

		// Handle other errors
		slog.Error("unhandled error",
			"error", err.Error(),
			"request_id", GetRequestID(c),
		)

		response.JSON(c, code, msg, nil)
	}
}
