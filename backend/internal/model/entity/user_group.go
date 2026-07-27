package entity

import (
	"time"

	"gorm.io/gorm"
)

// UserGroup 用户组表 GORM 实体
type UserGroup struct {
	ID        int64          `gorm:"primaryKey;autoIncrement"`
	Name      string         `gorm:"type:varchar(50);uniqueIndex;not null"`
	Remark    string         `gorm:"type:varchar(256)"`
	CreatedAt time.Time      `gorm:"autoCreateTime"`
	UpdatedAt time.Time      `gorm:"autoUpdateTime"`
	DeletedAt gorm.DeletedAt `gorm:"index"`
}

// TableName specifies the table name for GORM.
func (UserGroup) TableName() string {
	return "user_groups"
}
