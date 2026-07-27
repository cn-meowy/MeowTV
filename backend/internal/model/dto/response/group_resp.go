package response

import "time"

// GroupResp 用户组响应
type GroupResp struct {
	ID            int64    `json:"id"`
	Name          string   `json:"name"`
	Remark        string   `json:"remark"`
	ConfigKeys    []string `json:"config_keys,omitempty"`
	ResourceCount int      `json:"resource_count"`
	UserCount     int      `json:"user_count"`
	CreatedAt     string   `json:"created_at"`
	UpdatedAt     string   `json:"updated_at"`
}

// GroupListItem 用户组列表项
type GroupListItem struct {
	ID            int64     `json:"id"`
	Name          string    `json:"name"`
	Remark        string    `json:"remark"`
	ResourceCount int       `json:"resource_count"`
	UserCount     int       `json:"user_count"`
	CreatedAt     time.Time `json:"created_at"`
}
