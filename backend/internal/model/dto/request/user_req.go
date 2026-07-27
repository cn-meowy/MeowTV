package request

// UpdateProfileReq 修改个人信息请求
type UpdateProfileReq struct {
	Nickname *string `json:"nickname" validate:"omitempty,min=1,max=50"`
	Avatar   *string `json:"avatar" validate:"omitempty,max=500"`
}

// ChangePasswordReq 修改密码请求
type ChangePasswordReq struct {
	OldPassword string `json:"old_password" validate:"required,min=6,max=50"`
	NewPassword string `json:"new_password" validate:"required,min=6,max=50"`
}

// KickDeviceReq 踢掉指定设备请求
type KickDeviceReq struct {
	DeviceType int8 `json:"device_type" validate:"min=0,max=3"`
}
