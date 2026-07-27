package request

// CreateUserReq 管理员创建用户请求
type CreateUserReq struct {
	Username string `json:"username" validate:"required,min=3,max=50,alphanumunicode"`
	Password string `json:"password" validate:"required,min=6,max=50"`
	Nickname string `json:"nickname" validate:"omitempty,max=50"`
	Role     *int8  `json:"role" validate:"omitempty,min=0,max=1"`
}

// UpdateUserReq 管理员编辑用户请求
type UpdateUserReq struct {
	ID       int64   `json:"id" validate:"required"`
	Nickname *string `json:"nickname" validate:"omitempty,min=1,max=50"`
	Avatar   *string `json:"avatar" validate:"omitempty,max=500"`
	Role     *int8   `json:"role" validate:"omitempty,min=0,max=1"`
	Status   *int8   `json:"status" validate:"omitempty,min=0,max=1"`
	GroupID  *int64  `json:"group_id" validate:"omitempty"` // 所属用户组 ID，null 表示移除
}

// ResetPasswordReq 管理员重置密码请求
type ResetPasswordReq struct {
	ID          int64  `json:"id" validate:"required"`
	NewPassword string `json:"new_password" validate:"required,min=6,max=50"`
}

// UserListReq 用户列表请求
type UserListReq struct {
	Page    int    `json:"page" validate:"required,min=1"`
	Size    int    `json:"size" validate:"required,min=1,max=100"`
	Keyword string `json:"keyword" validate:"omitempty,max=50"`
	Role    *int8  `json:"role" validate:"omitempty,min=0,max=1"`
	Status  *int8  `json:"status" validate:"omitempty,min=0,max=1"`
}

// DeleteUserReq 管理员删除用户请求
type DeleteUserReq struct {
	ID int64 `json:"id" validate:"required"`
}

// KickUserReq 管理员踢用户下线请求
type KickUserReq struct {
	UserID     int64 `json:"user_id" validate:"required"`
	DeviceType *int8 `json:"device_type" validate:"omitempty,min=0,max=3"`
}
