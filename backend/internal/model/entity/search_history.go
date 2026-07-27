package entity

import (
	"time"

	"gorm.io/gorm"
)

// SearchHistory 搜索记录表 GORM 实体
type SearchHistory struct {
	ID        int64          `gorm:"primaryKey;autoIncrement"`
	UserID    int64          `gorm:"column:user_id;not null;uniqueIndex:uk_user_keyword"`
	Keyword   string         `gorm:"type:varchar(200);not null;uniqueIndex:uk_user_keyword"`
	CreatedAt time.Time      `gorm:"autoCreateTime"`
	UpdatedAt time.Time      `gorm:"autoUpdateTime"`
	DeletedAt gorm.DeletedAt `gorm:"index"`
}

// TableName specifies the table name for GORM.
func (SearchHistory) TableName() string {
	return "search_histories"
}
