package entity

import (
	"time"
)

// DoubanRank 影视榜单表 GORM 实体
// 存储每日从豆瓣获取的榜单和 Tags 数据，按日期 + 分类维度存储
type DoubanRank struct {
	ID          int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	RankDate    time.Time `gorm:"uniqueIndex:uk_rank_date_category;not null;type:date" json:"rank_date"`
	Category    string    `gorm:"uniqueIndex:uk_rank_date_category;size:32;not null" json:"category"`
	Type        string    `gorm:"size:16;not null" json:"type"`
	Tag         string    `gorm:"size:64;not null" json:"tag"`
	Data        string    `gorm:"type:text;not null" json:"data"`
	SyncStatus  string    `gorm:"size:16;not null;default:success" json:"sync_status"`
	RecordCount int       `gorm:"not null;default:0" json:"record_count"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// TableName specifies the table name for GORM.
func (DoubanRank) TableName() string {
	return "douban_rank"
}

// SyncStatus 常量
const (
	SyncStatusSuccess  = "success"
	SyncStatusFailed   = "failed"
	SyncStatusFallback = "fallback"
)
