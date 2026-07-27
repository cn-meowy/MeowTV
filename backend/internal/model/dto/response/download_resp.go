package response

import "cn.meow/meowtv/internal/model/entity"

// DownloadTaskItem 下载任务项
type DownloadTaskItem struct {
	ID                 int64                 `json:"id"`
	VodID              int64                 `json:"vod_id"`
	VodName            string                `json:"vod_name"`
	VodPic             string                `json:"vod_pic"`
	EpName             string                `json:"ep_name"`
	ResourceDomain     string                `json:"resource_domain"`
	ResourceName       string                `json:"resource_name"`
	GroupKey           string                `json:"group_key"`
	SourceIndex        int                   `json:"source_index"`
	EpIndex            int                   `json:"ep_index"`
	Status             entity.DownloadStatus `json:"status"`
	Progress           float64               `json:"progress"`
	TotalSegments      int                   `json:"total_segments"`
	DownloadedSegments int                   `json:"downloaded_segments"`
	FileSize           int64                 `json:"file_size"`
	ErrorMsg           string                `json:"error_msg"`
	CreatedAt          int64                 `json:"created_at"` // unix timestamp ms
	UpdatedAt          int64                 `json:"updated_at"` // unix timestamp ms
}

// DownloadListResp 下载任务列表响应
type DownloadListResp struct {
	Total int64              `json:"total"`
	Items []DownloadTaskItem `json:"items"`
}

// DownloadCreateResp 创建下载任务响应
type DownloadCreateResp struct {
	TaskIDs  []int64             `json:"task_ids"`
	Queued   int                 `json:"queued"`
	Skipped  int                 `json:"skipped"`
	Retried  int                 `json:"retried"`
	Messages []DownloadCreateMsg `json:"messages"`
}

// DownloadCreateMsg 创建任务提示消息
type DownloadCreateMsg struct {
	EpIndex int    `json:"ep_index"`
	EpName  string `json:"ep_name"`
	Type    string `json:"type"` // "completed" | "retried" | "active"
	Message string `json:"message"`
}

// DownloadCheckResp 检查本地下载文件响应
type DownloadCheckResp struct {
	Found      bool   `json:"found"`
	TaskID     int64  `json:"task_id"`
	FileURL    string `json:"file_url"`    // /api/download/file/{task_id}
	FileFormat string `json:"file_format"` // "mp4" 或 "ts"
}

// DownloadConfigResp 下载配置响应
type DownloadConfigResp struct {
	DownloadDir        string `json:"download_dir"`
	MaxConcurrent      int    `json:"max_concurrent"`
	SegmentConcurrency int    `json:"segment_concurrency"`
	FfmpegAvailable    bool   `json:"ffmpeg_available"`
	FfmpegVersion      string `json:"ffmpeg_version"`
}

// NewDownloadTaskItem 从 entity 创建响应项
func NewDownloadTaskItem(t *entity.DownloadTask) DownloadTaskItem {
	return DownloadTaskItem{
		ID:                 t.ID,
		VodID:              t.VodID,
		VodName:            t.VodName,
		VodPic:             t.VodPic,
		EpName:             t.EpName,
		ResourceDomain:     t.ResourceDomain,
		ResourceName:       t.ResourceName,
		GroupKey:           t.GroupKey,
		SourceIndex:        t.SourceIndex,
		EpIndex:            t.EpIndex,
		Status:             t.Status,
		Progress:           t.Progress,
		TotalSegments:      t.TotalSegments,
		DownloadedSegments: t.DownloadedSegments,
		FileSize:           t.FileSize,
		ErrorMsg:           t.ErrorMsg,
		CreatedAt:          t.CreatedAt.UnixMilli(),
		UpdatedAt:          t.UpdatedAt.UnixMilli(),
	}
}
