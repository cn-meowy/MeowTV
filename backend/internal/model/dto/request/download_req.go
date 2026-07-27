package request

// DownloadItem 下载项
type DownloadItem struct {
	SourceIndex int    `json:"source_index" validate:"min=0"`
	EpIndex     int    `json:"ep_index" validate:"min=0"`
	EpName      string `json:"ep_name" validate:"required"`
	M3u8URL     string `json:"m3u8_url" validate:"required,url"`
}

// DownloadCreateReq 创建下载任务请求
type DownloadCreateReq struct {
	VodID          int64          `json:"vod_id" validate:"required"`
	VodName        string         `json:"vod_name" validate:"required"`
	VodPic         string         `json:"vod_pic"`
	ResourceDomain string         `json:"resource_domain" validate:"required"`
	ResourceName   string         `json:"resource_name"`
	GroupKey       string         `json:"group_key"`
	Items          []DownloadItem `json:"items" validate:"required,min=1,dive"`
}

// DownloadListReq 下载任务列表请求
type DownloadListReq struct {
	Status *int `json:"status"` // 可选：按状态过滤
	Limit  int  `json:"limit" validate:"min=1,max=200"`
	Offset int  `json:"offset" validate:"min=0"`
}

// DownloadTaskIDReq 通用任务 ID 请求（取消/删除/重试）
type DownloadTaskIDReq struct {
	TaskID int64 `json:"task_id" validate:"required"`
}

// DownloadCheckReq 检查是否有本地下载文件请求
type DownloadCheckReq struct {
	ResourceDomain string `json:"resource_domain" validate:"required"`
	VodID          int64  `json:"vod_id" validate:"required"`
	SourceIndex    int    `json:"source_index" validate:"min=0"`
	EpIndex        int    `json:"ep_index" validate:"min=0"`
}

// DownloadConfigUpdateReq 更新下载配置请求
type DownloadConfigUpdateReq struct {
	DownloadDir        string `json:"download_dir"`
	MaxConcurrent      int    `json:"max_concurrent" validate:"min=1,max=10"`
	SegmentConcurrency int    `json:"segment_concurrency" validate:"min=1,max=50"`
}
