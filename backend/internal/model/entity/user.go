package entity

import (
	"time"

	"gorm.io/gorm"
)

// User 用户表 GORM 实体
type User struct {
	ID           int64          `gorm:"primaryKey;autoIncrement"`
	Username     string         `gorm:"type:varchar(50);uniqueIndex;not null"`
	PasswordHash string         `gorm:"column:password_hash;type:varchar(255);not null"`
	Nickname     string         `gorm:"type:varchar(50);not null"`
	Avatar       string         `gorm:"type:varchar(500);default:''"`
	Role         Role           `gorm:"type:smallint;not null;default:0"`
	Status       Status         `gorm:"type:smallint;not null;default:1"`
	GroupID      *int64         `gorm:"index;default:null"` // 所属用户组 ID，null 表示未分配
	LastLoginAt  *time.Time     `gorm:"column:last_login_at"`
	CreatedAt    time.Time      `gorm:"autoCreateTime"`
	UpdatedAt    time.Time      `gorm:"autoUpdateTime"`
	DeletedAt    gorm.DeletedAt `gorm:"index"`
}

// TableName specifies the table name for GORM.
func (User) TableName() string {
	return "users"
}
