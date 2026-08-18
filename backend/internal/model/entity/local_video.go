package entity

import "time"

// LocalVideo 本地视频资源实体（Apple Store 审核演示模式）
// 字段映射 MacCMS v10 的 vod 结构，使本地扫描数据可直接伪装为 MacCMS 站点数据，
// 复用现有的搜索/详情/分页接口和前端播放流程。
type LocalVideo struct {
	ID      int64  `gorm:"primaryKey;autoIncrement" json:"id"`
	VodID   int64  `gorm:"uniqueIndex;column:vod_id;not null" json:"vod_id"`
	VodName string `gorm:"column:vod_name;type:varchar(255);not null;index" json:"vod_name"`
	VodSub  string `gorm:"column:vod_sub;type:varchar(255);default:''" json:"vod_sub"`
	VodEn   string `gorm:"column:vod_en;type:varchar(255);default:''" json:"vod_en"`
	// VodClass 对应 MacCMS 的 type_name + vod_class，用文件夹名作为分类
	VodClass    string `gorm:"column:vod_class;type:varchar(255);default:'';index" json:"vod_class"`
	VodPic      string `gorm:"column:vod_pic;type:varchar(512);default:''" json:"vod_pic"`
	VodActor    string `gorm:"column:vod_actor;type:varchar(512);default:''" json:"vod_actor"`
	VodDirector string `gorm:"column:vod_director;type:varchar(512);default:''" json:"vod_director"`
	VodBlurb    string `gorm:"column:vod_blurb;type:text" json:"vod_blurb"`
	VodContent  string `gorm:"column:vod_content;type:text" json:"vod_content"`
	VodRemarks  string `gorm:"column:vod_remarks;type:varchar(255);default:''" json:"vod_remarks"`
	VodArea     string `gorm:"column:vod_area;type:varchar(128);default:''" json:"vod_area"`
	VodLang     string `gorm:"column:vod_lang;type:varchar(128);default:''" json:"vod_lang"`
	VodYear     string `gorm:"column:vod_year;type:varchar(32);default:''" json:"vod_year"`
	VodScore    string `gorm:"column:vod_score;type:varchar(16);default:''" json:"vod_score"`
	// VodPlayFrom / VodPlayURL 采用 MacCMS 标准格式：
	//   vod_play_from = "local"
	//   vod_play_url  = "local$$$local$$第1集$$/api/download/file/{taskID}#"
	VodPlayFrom string `gorm:"column:vod_play_from;type:varchar(255);default:''" json:"vod_play_from"`
	VodPlayURL  string `gorm:"column:vod_play_url;type:text" json:"vod_play_url"`
	TypeName    string `gorm:"column:type_name;type:varchar(128);default:''" json:"type_name"`
	TypeID1     int    `gorm:"column:type_id_1;default:0" json:"type_id_1"`
	// FilePath 本地视频文件绝对路径
	FilePath string `gorm:"column:file_path;type:varchar(512);default:''" json:"file_path"`
	// DownloadTaskID 关联的 download_task 记录 ID（用于 /api/download/file/:id 播放）
	DownloadTaskID int64     `gorm:"column:download_task_id;default:0" json:"download_task_id"`
	CreatedAt      time.Time `gorm:"autoCreateTime" json:"created_at"`
	UpdatedAt      time.Time `gorm:"autoUpdateTime" json:"updated_at"`
}

// TableName specifies the table name for GORM.
func (LocalVideo) TableName() string {
	return "local_video"
}
