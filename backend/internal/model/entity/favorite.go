package entity

import (
	"time"

	"gorm.io/gorm"
)

// Favorite 收藏表 GORM 实体
type Favorite struct {
	ID             int64          `gorm:"primaryKey;autoIncrement"`
	UserID         int64          `gorm:"column:user_id;not null;uniqueIndex:uk_fav_user_vod_douban"`
	VodID          int64          `gorm:"column:vod_id;not null;default:0;uniqueIndex:uk_fav_user_vod_douban"`
	VodName        string         `gorm:"column:vod_name;type:varchar(200);not null;default:''"`
	VodPic         string         `gorm:"column:vod_pic;type:varchar(500);default:''"`
	DoubanID       string         `gorm:"column:douban_id;type:varchar(50);not null;default:'';uniqueIndex:uk_fav_user_vod_douban"`
	GroupKey       string         `gorm:"column:group_key;type:varchar(200);not null;default:''"`
	Site           string         `gorm:"column:site;type:varchar(100);not null;default:''"`
	ResourceDomain string         `gorm:"column:resource_domain;type:varchar(100);not null;default:'';uniqueIndex:uk_fav_user_vod_douban"`
	ResourceName   string         `gorm:"column:resource_name;type:varchar(100);not null;default:''"`
	CreatedAt      time.Time      `gorm:"autoCreateTime"`
	DeletedAt      gorm.DeletedAt `gorm:"index"`
}

// TableName specifies the table name for GORM.
func (Favorite) TableName() string {
	return "favorites"
}
