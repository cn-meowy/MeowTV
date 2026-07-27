package response

// PlayHistoryItem 播放历史项
type PlayHistoryItem struct {
	ID             int64   `json:"id"`
	VodID          int64   `json:"vod_id"`
	VodName        string  `json:"vod_name"`
	VodPic         string  `json:"vod_pic"`
	ResourceDomain string  `json:"resource_domain"`
	ResourceName   string  `json:"resource_name"`
	GroupKey       string  `json:"group_key"`
	SourceIndex    int     `json:"source_index"`
	EpIndex        int     `json:"ep_index"`
	EpName         string  `json:"ep_name"`
	Progress       float64 `json:"progress"`
	CurrentTime    float64 `json:"current_time"`
	Duration       float64 `json:"duration"`
	CreatedAt      int64   `json:"created_at"` // unix timestamp ms
	UpdatedAt      int64   `json:"updated_at"` // unix timestamp ms
}

// PlayHistoryListResp 播放历史列表响应
type PlayHistoryListResp struct {
	Total int64             `json:"total"`
	Items []PlayHistoryItem `json:"items"`
}
