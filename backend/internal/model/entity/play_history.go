package entity

import (
	"time"

	"gorm.io/gorm"
)

// PlayHistory 播放历史表 GORM 实体
type PlayHistory struct {
	ID             int64          `gorm:"primaryKey;autoIncrement"`
	UserID         int64          `gorm:"column:user_id;not null;uniqueIndex:uk_user_vod_resource"`
	VodID          int64          `gorm:"column:vod_id;not null;uniqueIndex:uk_user_vod_resource"`
	VodName        string         `gorm:"column:vod_name;type:varchar(200);not null;default:''"`
	VodPic         string         `gorm:"column:vod_pic;type:varchar(500);default:''"`
	ResourceDomain string         `gorm:"column:resource_domain;type:varchar(100);not null;default:'';uniqueIndex:uk_user_vod_resource"`
	ResourceName   string         `gorm:"column:resource_name;type:varchar(100);not null;default:''"`
	GroupKey       string         `gorm:"column:group_key;type:varchar(200);not null;default:''"`
	SourceIndex    int            `gorm:"column:source_index;not null;default:0"`
	EpIndex        int            `gorm:"column:ep_index;not null;default:0;uniqueIndex:uk_user_vod_resource"`
	EpName         string         `gorm:"column:ep_name;type:varchar(200);not null;default:''"`
	Progress       float64        `gorm:"column:progress;type:REAL;not null;default:0"`
	CurrentTime    float64        `gorm:"column:current_time;type:REAL;not null;default:0"`
	Duration       float64        `gorm:"column:duration;type:REAL;not null;default:0"`
	CreatedAt      time.Time      `gorm:"autoCreateTime"`
	UpdatedAt      time.Time      `gorm:"autoUpdateTime"`
	DeletedAt      gorm.DeletedAt `gorm:"index"`
}

// TableName specifies the table name for GORM.
func (PlayHistory) TableName() string {
	return "play_histories"
}
