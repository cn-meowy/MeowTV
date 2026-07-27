package entity

import (
	"time"
)

// SysConfig 系统配置表 GORM 实体
// 所有 value 存储为 string，类型转换在业务代码中处理
type SysConfig struct {
	ID          int64     `gorm:"primaryKey;autoIncrement" json:"id"`
	ConfigKey   string    `gorm:"uniqueIndex;size:128;not null" json:"config_key"`
	ConfigGroup string    `gorm:"index;size:64;not null" json:"config_group"`
	Title       string    `gorm:"size:256" json:"title"`
	Title1      string    `gorm:"size:128" json:"title1"`
	Title2      string    `gorm:"size:128" json:"title2"`
	Title3      string    `gorm:"size:128" json:"title3"`
	Title4      string    `gorm:"size:128" json:"title4"`
	Title5      string    `gorm:"size:128" json:"title5"`
	Title6      string    `gorm:"size:128" json:"title6"`
	Value1      string    `gorm:"size:1024" json:"value1"`
	Value2      string    `gorm:"size:1024" json:"value2"`
	Value3      string    `gorm:"size:1024" json:"value3"`
	Value4      string    `gorm:"size:1024" json:"value4"`
	Value5      string    `gorm:"size:1024" json:"value5"`
	Value6      string    `gorm:"size:1024" json:"value6"`
	SortOrder   int       `gorm:"default:0" json:"sort_order"`
	IsEnabled   bool      `gorm:"default:true" json:"is_enabled"`
	Remark      string    `gorm:"size:512" json:"remark"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// TableName specifies the table name for GORM.
func (SysConfig) TableName() string {
	return "sys_config"
}
