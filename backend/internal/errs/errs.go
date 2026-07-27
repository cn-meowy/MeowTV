package errs

import (
	"fmt"
	"runtime"
)

// AppError is the application-level error type.
// Code is the HTTP status code exposed to clients.
// Msg is the user-readable message exposed to clients.
// Inner and Stack are internal details, never exposed to clients.
type AppError struct {
	Code  int    `json:"code"`
	Msg   string `json:"msg"`
	Inner error  `json:"-"`
	Stack string `json:"-"`
}

// Error implements the error interface.
func (e *AppError) Error() string {
	if e.Inner != nil {
		return fmt.Sprintf("[%d] %s: %v", e.Code, e.Msg, e.Inner)
	}
	return fmt.Sprintf("[%d] %s", e.Code, e.Msg)
}

// Unwrap returns the wrapped inner error for errors.Is/As compatibility.
func (e *AppError) Unwrap() error {
	return e.Inner
}

// New creates a new AppError with the given code and message.
// The stack trace is captured at creation time.
func New(code int, msg string) *AppError {
	return &AppError{
		Code:  code,
		Msg:   msg,
		Stack: captureStack(),
	}
}

// Newf creates a new AppError with formatted message.
func Newf(code int, format string, args ...interface{}) *AppError {
	return New(code, fmt.Sprintf(format, args...))
}

// captureStack captures the current goroutine stack trace.
func captureStack() string {
	buf := make([]byte, 4096)
	n := runtime.Stack(buf, false)
	return string(buf[:n])
}
