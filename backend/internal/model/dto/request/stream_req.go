package request

// StreamProgressReq 上报播放进度请求
type StreamProgressReq struct {
	Session       string `json:"session" validate:"required"`
	CurrentIndex  int    `json:"current_index" validate:"min=0"`
	BufferedAhead int    `json:"buffered_ahead" validate:"min=0"`
}

// StreamSaveReq 保存为下载任务请求
type StreamSaveReq struct {
	Session string `json:"session" validate:"required"`
	VodID   int64  `json:"vod_id" validate:"required"`
	VodName string `json:"vod_name" validate:"required"`
	EpName  string `json:"ep_name" validate:"required"`
}

// StreamSessionReq 关闭会话请求
type StreamSessionReq struct {
	Session string `json:"session" validate:"required"`
}

// StreamProxyM3U8Req 代理 m3u8 请求（Query 参数）
type StreamProxyM3U8Req struct {
	URL string `query:"url" validate:"required,url"`
}

// StreamProxyTSReq 代理 TS 分片请求（Query 参数）
type StreamProxyTSReq struct {
	Session string `query:"session" validate:"required"`
	Index   int    `query:"index" validate:"min=0"`
	URL     string `query:"url" validate:"required"`
}

// StreamCheckReq m3u8 链接检测请求
type StreamCheckReq struct {
	URLs []string `json:"urls" validate:"required,min=1,max=50,dive,url"`
}
