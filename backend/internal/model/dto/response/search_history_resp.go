package response

// SearchHistoryItem 搜索历史项
type SearchHistoryItem struct {
	ID        int64  `json:"id"`
	Keyword   string `json:"keyword"`
	UpdatedAt int64  `json:"updated_at"` // unix timestamp ms
}
