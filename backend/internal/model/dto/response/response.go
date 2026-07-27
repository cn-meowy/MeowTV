package response

import (
	"log/slog"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
)

// Response is the unified API response structure.
// All API responses must conform to this format.
type Response struct {
	Code int         `json:"code"`
	Msg  string      `json:"msg"`
	Data interface{} `json:"data,omitempty"`
}

// OK sends a successful response with code 200.
func OK(c echo.Context, data interface{}) error {
	return JSON(c, 200, "success", data)
}

// OKMsg sends a successful response with a custom message.
func OKMsg(c echo.Context, msg string, data interface{}) error {
	return JSON(c, 200, msg, data)
}

// Fail sends an error response based on the AppError.
func Fail(c echo.Context, appErr *errs.AppError) error {
	if appErr.Code >= 500 {
		slog.Error("internal server error",
			"code", appErr.Code,
			"msg", appErr.Msg,
			"inner", appErr.Inner,
		)
	}
	return JSON(c, appErr.Code, appErr.Msg, nil)
}

// FailWithData sends an error response with additional data.
func FailWithData(c echo.Context, appErr *errs.AppError, data interface{}) error {
	if appErr.Code >= 500 {
		slog.Error("internal server error",
			"code", appErr.Code,
			"msg", appErr.Msg,
			"inner", appErr.Inner,
		)
	}
	return JSON(c, appErr.Code, appErr.Msg, data)
}

// JSON sends a JSON response with the given code, message, and data.
func JSON(c echo.Context, code int, msg string, data interface{}) error {
	return c.JSON(code, Response{
		Code: code,
		Msg:  msg,
		Data: data,
	})
}

// Paginated represents a paginated list response.
type Paginated struct {
	Items      interface{} `json:"items"`
	Total      int64       `json:"total"`
	Page       int         `json:"page"`
	Size       int         `json:"size"`
	TotalPages int         `json:"total_pages"`
}

// NewPaginated creates a new Paginated response.
func NewPaginated(items interface{}, total int64, page, size int) *Paginated {
	totalPages := int(total) / size
	if int(total)%size != 0 {
		totalPages++
	}
	return &Paginated{
		Items:      items,
		Total:      total,
		Page:       page,
		Size:       size,
		TotalPages: totalPages,
	}
}
