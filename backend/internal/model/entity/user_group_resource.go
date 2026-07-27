package entity

import "time"

// UserGroupResource 用户组资源关联表 GORM 实体
type UserGroupResource struct {
	ID        int64     `gorm:"primaryKey;autoIncrement"`
	GroupID   int64     `gorm:"uniqueIndex:idx_group_resource;not null"`
	ConfigKey string    `gorm:"type:varchar(128);uniqueIndex:idx_group_resource;not null"`
	CreatedAt time.Time `gorm:"autoCreateTime"`
}

// TableName specifies the table name for GORM.
func (UserGroupResource) TableName() string {
	return "user_group_resources"
}
