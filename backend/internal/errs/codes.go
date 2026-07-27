package errs

// Predefined application errors.
// Use these as base errors and wrap with additional context.

var (
	// ErrBadRequest indicates invalid request parameters.
	ErrBadRequest = New(400, "请求参数错误")

	// ErrUnauthorized indicates missing or invalid authentication.
	ErrUnauthorized = New(401, "未认证或认证已过期")

	// ErrForbidden indicates insufficient permissions.
	ErrForbidden = New(403, "无权限访问")

	// ErrNotFound indicates the requested resource does not exist.
	ErrNotFound = New(404, "资源不存在")

	// ErrConflict indicates a resource conflict (e.g., duplicate entry).
	ErrConflict = New(409, "资源冲突")

	// ErrTooManyReq indicates rate limit exceeded.
	ErrTooManyReq = New(429, "请求过于频繁")

	// ErrInternal indicates an internal server error.
	ErrInternal = New(500, "内部服务错误")

	// ErrServiceUnavailable indicates the service is temporarily unavailable.
	ErrServiceUnavailable = New(503, "服务暂不可用")
)
