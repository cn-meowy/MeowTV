package request

// CreateGroupReq 创建用户组请求
type CreateGroupReq struct {
	Name   string `json:"name" validate:"required,min=1,max=50"`
	Remark string `json:"remark" validate:"omitempty,max=256"`
}

// UpdateGroupReq 更新用户组请求
type UpdateGroupReq struct {
	ID     int64   `json:"id" validate:"required"`
	Name   *string `json:"name" validate:"omitempty,min=1,max=50"`
	Remark *string `json:"remark" validate:"omitempty,max=256"`
}

// DeleteGroupReq 删除用户组请求
type DeleteGroupReq struct {
	ID int64 `json:"id" validate:"required"`
}

// GroupListReq 用户组列表请求
type GroupListReq struct {
	Page    int    `json:"page" validate:"required,min=1"`
	Size    int    `json:"size" validate:"required,min=1,max=100"`
	Keyword string `json:"keyword" validate:"omitempty,max=50"`
}

// SetGroupResourcesReq 设置用户组关联的资源站点
type SetGroupResourcesReq struct {
	GroupID    int64    `json:"group_id" validate:"required"`
	ConfigKeys []string `json:"config_keys" validate:"required,max=200"`
}

// SetUserGroupReq 设置用户所属用户组
type SetUserGroupReq struct {
	UserID  int64  `json:"user_id" validate:"required"`
	GroupID *int64 `json:"group_id" validate:"omitempty"` // null 表示移除用户组
}

// GroupDetailReq 用户组详情请求
type GroupDetailReq struct {
	ID int64 `json:"id" validate:"required"`
}
