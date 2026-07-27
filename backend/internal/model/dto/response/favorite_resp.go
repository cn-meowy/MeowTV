package response

// FavoriteItem 收藏项
type FavoriteItem struct {
	ID             int64  `json:"id"`
	VodID          int64  `json:"vod_id"`
	VodName        string `json:"vod_name"`
	VodPic         string `json:"vod_pic"`
	DoubanID       string `json:"douban_id"`
	GroupKey       string `json:"group_key"`
	Site           string `json:"site"`
	ResourceDomain string `json:"resource_domain"`
	ResourceName   string `json:"resource_name"`
	CreatedAt      int64  `json:"created_at"` // unix timestamp ms
}

// FavoriteListResp 收藏列表响应
type FavoriteListResp struct {
	Total int64          `json:"total"`
	Items []FavoriteItem `json:"items"`
}

// FavoriteCheckResp 检查是否已收藏响应
type FavoriteCheckResp struct {
	IsFavorite bool `json:"is_favorite"`
}
