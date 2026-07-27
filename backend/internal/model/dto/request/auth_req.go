package request

// LoginReq 账号密码登录请求
type LoginReq struct {
	Username   string `json:"username" validate:"required,min=3,max=50"`
	Password   string `json:"password" validate:"required,min=6,max=50"`
	DeviceType int8   `json:"device_type" validate:"min=0,max=3"`
	DeviceID   string `json:"device_id" validate:"required,min=1,max=128"`
	DeviceName string `json:"device_name" validate:"required,min=1,max=200"`
}

// RefreshReq 刷新 Token 请求
type RefreshReq struct {
	RefreshToken string `json:"refresh_token" validate:"required"`
}

// LogoutReq 登出请求（无需额外字段，从 JWT 提取信息）
type LogoutReq struct{}
