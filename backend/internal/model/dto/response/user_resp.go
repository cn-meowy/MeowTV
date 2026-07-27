package response

// ProfileResp 用户个人信息响应
type ProfileResp struct {
	ID        int64  `json:"id"`
	Username  string `json:"username"`
	Nickname  string `json:"nickname"`
	Avatar    string `json:"avatar"`
	Role      int8   `json:"role"`
	Status    int8   `json:"status"`
	GroupID   *int64 `json:"group_id,omitempty"`
	GroupName string `json:"group_name,omitempty"`
}

// DeviceInfo 设备信息
type DeviceInfo struct {
	DeviceID     string `json:"device_id"`
	DeviceName   string `json:"device_name"`
	DeviceType   int8   `json:"device_type"`
	LastActiveAt int64  `json:"last_active_at"`
	Online       bool   `json:"online"`
}

// DeviceListResp 在线设备列表响应
type DeviceListResp struct {
	Devices []DeviceInfo `json:"devices"`
}

// UserListItem 用户列表项
type UserListItem struct {
	ID          int64   `json:"id"`
	Username    string  `json:"username"`
	Nickname    string  `json:"nickname"`
	Avatar      string  `json:"avatar"`
	Role        int8    `json:"role"`
	Status      int8    `json:"status"`
	GroupID     *int64  `json:"group_id,omitempty"`
	GroupName   string  `json:"group_name,omitempty"`
	LastLoginAt *string `json:"last_login_at"`
	CreatedAt   string  `json:"created_at"`
}

// CreateUserResp 创建用户响应
type CreateUserResp struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	Nickname string `json:"nickname"`
	Role     int8   `json:"role"`
}
