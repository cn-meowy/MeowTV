package request

// SearchReq 聚合搜索请求
type SearchReq struct {
	Q         string   `json:"q" validate:"required,max=200"`
	DoubanID  string   `json:"douban_id,omitempty" validate:"omitempty,max=32"`
	Resources []string `json:"resources" validate:"required,min=1,max=50"`
}
