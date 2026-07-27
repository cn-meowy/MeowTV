package request

// PlayHistoryListReq 播放历史列表请求
type PlayHistoryListReq struct {
	Limit  int `json:"limit" validate:"min=1,max=200"`
	Offset int `json:"offset" validate:"min=0"`
}

// PlayHistoryGetReq 查询单条播放记录请求
type PlayHistoryGetReq struct {
	VodID          int64  `json:"vod_id" validate:"required"`
	ResourceDomain string `json:"resource_domain" validate:"required"`
	EpIndex        int    `json:"ep_index"`
}

// PlayHistoryUpsertReq 新增/更新播放记录请求（完整数据）
type PlayHistoryUpsertReq struct {
	VodID          int64   `json:"vod_id" validate:"required"`
	VodName        string  `json:"vod_name"`
	VodPic         string  `json:"vod_pic"`
	ResourceDomain string  `json:"resource_domain" validate:"required"`
	ResourceName   string  `json:"resource_name"`
	GroupKey       string  `json:"group_key"`
	SourceIndex    int     `json:"source_index"`
	EpIndex        int     `json:"ep_index"`
	EpName         string  `json:"ep_name"`
	Progress       float64 `json:"progress" validate:"min=0,max=100"`
	CurrentTime    float64 `json:"current_time"`
	Duration       float64 `json:"duration"`
}

// PlayHistoryProgressReq 进度更新（upsert 语义：记录不存在时自动创建）
type PlayHistoryProgressReq struct {
	VodID          int64   `json:"vod_id" validate:"required"`
	VodName        string  `json:"vod_name"`
	VodPic         string  `json:"vod_pic"`
	ResourceDomain string  `json:"resource_domain" validate:"required"`
	ResourceName   string  `json:"resource_name"`
	GroupKey       string  `json:"group_key"`
	Progress       float64 `json:"progress" validate:"min=0,max=100"`
	CurrentTime    float64 `json:"current_time"`
	Duration       float64 `json:"duration"`
	SourceIndex    int     `json:"source_index"`
	EpIndex        int     `json:"ep_index"`
	EpName         string  `json:"ep_name"`
	// 流调度相关字段（可选）
	Session       string `json:"session"`        // 流会话 key
	CurrentIndex  int    `json:"current_index"`  // 当前播放分片索引
	BufferedAhead int    `json:"buffered_ahead"` // 前置缓冲分片数
}

// PlayHistoryDeleteReq 删除播放记录请求
type PlayHistoryDeleteReq struct {
	ID int64 `json:"id" validate:"required"`
}
