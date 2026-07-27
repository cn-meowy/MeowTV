package request

// FavoriteListReq 收藏列表请求
type FavoriteListReq struct {
	Limit   int    `json:"limit" validate:"min=1,max=200"`
	Offset  int    `json:"offset" validate:"min=0"`
	Keyword string `json:"keyword"`
}

// FavoriteAddReq 添加收藏请求
// 规则：vod_id + resource_domain（有资源来源）或 douban_id（无资源来源）至少有一组
type FavoriteAddReq struct {
	VodID          int64  `json:"vod_id"`
	VodName        string `json:"vod_name" validate:"required"`
	VodPic         string `json:"vod_pic"`
	DoubanID       string `json:"douban_id"`
	GroupKey       string `json:"group_key"`
	Site           string `json:"site"`
	ResourceDomain string `json:"resource_domain"`
	ResourceName   string `json:"resource_name"`
}

// FavoriteRemoveReq 取消收藏请求
// 规则：vod_id + resource_domain 或 douban_id 至少有一组
type FavoriteRemoveReq struct {
	VodID          int64  `json:"vod_id"`
	ResourceDomain string `json:"resource_domain"`
	DoubanID       string `json:"douban_id"`
}

// FavoriteCheckReq 检查是否已收藏请求
// 规则：vod_id + resource_domain 或 douban_id 至少有一组
type FavoriteCheckReq struct {
	VodID          int64  `json:"vod_id"`
	ResourceDomain string `json:"resource_domain"`
	DoubanID       string `json:"douban_id"`
}
