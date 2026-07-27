package request

// SearchHistoryListReq 搜索历史列表请求
type SearchHistoryListReq struct {
	Limit int `json:"limit" validate:"min=1,max=50"`
}

// SearchHistoryAddReq 新增搜索记录请求
type SearchHistoryAddReq struct {
	Keyword string `json:"keyword" validate:"required,min=1,max=200"`
}

// SearchHistoryDeleteReq 删除搜索记录请求
type SearchHistoryDeleteReq struct {
	ID int64 `json:"id" validate:"required"`
}
