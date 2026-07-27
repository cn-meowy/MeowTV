package request

// ResourceSubscribeUpdateReq 更新资源订阅配置请求
type ResourceSubscribeUpdateReq struct {
	SubscribeURL  *string `json:"subscribe_url" validate:"omitempty,url,max=1024"`
	AutoSubscribe *bool   `json:"auto_subscribe"`
	CronExpr      *string `json:"cron_expr" validate:"omitempty,max=64"`
}

// ResourceDetailReq 资源详情查询请求
type ResourceDetailReq struct {
	Site  string `json:"site" validate:"required,max=256"`
	VodID int64  `json:"vod_id" validate:"required,min=1"`
}

// ResourcePageReq 资源分页查询请求
type ResourcePageReq struct {
	Page     int    `json:"page" validate:"required,min=1"`
	PageSize int    `json:"page_size" validate:"required,min=1,max=100"`
	Keyword  string `json:"keyword,omitempty" validate:"omitempty,max=200"`
	Resource string `json:"resource" validate:"required,max=256"`
}
