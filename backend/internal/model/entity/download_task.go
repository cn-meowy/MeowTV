package entity

import "time"

// DownloadStatus 下载任务状态枚举
type DownloadStatus int

const (
	DownloadStatusQueued      DownloadStatus = iota // 0 - 排队中
	DownloadStatusParsing                           // 1 - 解析中
	DownloadStatusDownloading                       // 2 - 下载中
	DownloadStatusMerging                           // 3 - 合并中
	DownloadStatusCompleted                         // 4 - 已完成
	DownloadStatusFailed                            // 5 - 失败
	DownloadStatusCancelled                         // 6 - 已取消
)

func (s DownloadStatus) String() string {
	switch s {
	case DownloadStatusQueued:
		return "queued"
	case DownloadStatusParsing:
		return "parsing"
	case DownloadStatusDownloading:
		return "downloading"
	case DownloadStatusMerging:
		return "merging"
	case DownloadStatusCompleted:
		return "completed"
	case DownloadStatusFailed:
		return "failed"
	case DownloadStatusCancelled:
		return "cancelled"
	default:
		return "unknown"
	}
}

// IsTerminal 是否为终态（不可再推进）
func (s DownloadStatus) IsTerminal() bool {
	return s == DownloadStatusCompleted || s == DownloadStatusFailed || s == DownloadStatusCancelled
}

// DownloadTask 下载任务表 GORM 实体
type DownloadTask struct {
	ID                 int64          `gorm:"primaryKey;autoIncrement"`
	UserID             int64          `gorm:"column:user_id;not null;index"`
	VodID              int64          `gorm:"column:vod_id;not null"`
	VodName            string         `gorm:"column:vod_name;type:varchar(255);not null;default:''"`
	VodPic             string         `gorm:"column:vod_pic;type:varchar(512);default:''"`
	ResourceDomain     string         `gorm:"column:resource_domain;type:varchar(255);not null;default:''"`
	ResourceName       string         `gorm:"column:resource_name;type:varchar(255);not null;default:''"`
	GroupKey           string         `gorm:"column:group_key;type:varchar(128);not null;default:''"`
	SourceIndex        int            `gorm:"column:source_index;not null;default:0"`
	EpIndex            int            `gorm:"column:ep_index;not null;default:0"`
	EpName             string         `gorm:"column:ep_name;type:varchar(255);not null;default:''"`
	M3u8URL            string         `gorm:"column:m3u8_url;type:varchar(1024);not null"`
	Status             DownloadStatus `gorm:"column:status;not null;default:0"`
	Progress           float64        `gorm:"column:progress;not null;default:0"`
	TotalSegments      int            `gorm:"column:total_segments;not null;default:0"`
	DownloadedSegments int            `gorm:"column:downloaded_segments;not null;default:0"`
	FileSize           int64          `gorm:"column:file_size;not null;default:0"`
	FilePath           string         `gorm:"column:file_path;type:varchar(512);default:''"`
	ErrorMsg           string         `gorm:"column:error_msg;type:varchar(512);default:''"`
	CreatedAt          time.Time      `gorm:"autoCreateTime"`
	UpdatedAt          time.Time      `gorm:"autoUpdateTime"`
}

// TableName specifies the table name for GORM.
func (DownloadTask) TableName() string {
	return "download_tasks"
}
