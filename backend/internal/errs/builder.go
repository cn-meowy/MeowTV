package errs

import (
	"fmt"
)

// Wrap wraps an underlying error with an AppError, preserving the original error.
// Use this when converting lower-level errors (e.g., GORM errors, network errors) to AppError.
func Wrap(err error, appErr *AppError) *AppError {
	return &AppError{
		Code:  appErr.Code,
		Msg:   appErr.Msg,
		Inner: err,
		Stack: captureStack(),
	}
}

// Wrapf wraps an underlying error with an AppError and formatted message.
func Wrapf(err error, code int, format string, args ...interface{}) *AppError {
	return &AppError{
		Code:  code,
		Msg:   fmt.Sprintf(format, args...),
		Inner: err,
		Stack: captureStack(),
	}
}

// WithMsg returns a new AppError with the same code but different message.
// Use this to provide more context-specific messages.
func WithMsg(msg string, appErr *AppError) *AppError {
	return &AppError{
		Code:  appErr.Code,
		Msg:   msg,
		Inner: appErr.Inner,
		Stack: captureStack(),
	}
}

// WithMsgf returns a new AppError with the same code but formatted message.
func WithMsgf(appErr *AppError, format string, args ...interface{}) *AppError {
	return WithMsg(fmt.Sprintf(format, args...), appErr)
}

// IsAppError checks whether the given error is an AppError.
// Use this for type assertion: if errs.IsAppError(err) { ... }
func IsAppError(err error) bool {
	if err == nil {
		return false
	}
	_, ok := err.(*AppError)
	return ok
}

// AsAppError performs a type assertion to *AppError.
// Returns nil if the error is not an AppError.
func AsAppError(err error) *AppError {
	if err == nil {
		return nil
	}
	appErr, ok := err.(*AppError)
	if !ok {
		return nil
	}
	return appErr
}

// NewWithStack creates a new AppError and captures the stack trace.
// This is an alias for New to make the builder pattern more readable.
func NewWithStack(code int, msg string) *AppError {
	return New(code, msg)
}
