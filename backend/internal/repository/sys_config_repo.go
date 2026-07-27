package repository

import (
	"context"

	"gorm.io/gorm"

	"cn.meow/meowtv/internal/model/entity"
)

// SysConfigRepository 系统配置数据层接口
type SysConfigRepository interface {
	GetByKey(ctx context.Context, key string) (*entity.SysConfig, error)
	ListByGroup(ctx context.Context, group string) ([]*entity.SysConfig, error)
	ListEnabledByGroup(ctx context.Context, group string) ([]*entity.SysConfig, error)
	ListAll(ctx context.Context) ([]*entity.SysConfig, error)
	Create(ctx context.Context, cfg *entity.SysConfig) error
	Update(ctx context.Context, cfg *entity.SysConfig) error
	Delete(ctx context.Context, id int64) error
}

// sysConfigRepository GORM 实现
type sysConfigRepository struct {
	db *gorm.DB
}

// NewSysConfigRepository 创建系统配置 Repository
func NewSysConfigRepository(db *gorm.DB) SysConfigRepository {
	return &sysConfigRepository{db: db}
}

func (r *sysConfigRepository) GetByKey(ctx context.Context, key string) (*entity.SysConfig, error) {
	var cfg entity.SysConfig
	if err := r.db.WithContext(ctx).Where("config_key = ?", key).First(&cfg).Error; err != nil {
		return nil, err
	}
	return &cfg, nil
}

func (r *sysConfigRepository) ListByGroup(ctx context.Context, group string) ([]*entity.SysConfig, error) {
	var list []*entity.SysConfig
	if err := r.db.WithContext(ctx).Where("config_group = ?", group).Order("sort_order ASC, id ASC").Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}

func (r *sysConfigRepository) ListEnabledByGroup(ctx context.Context, group string) ([]*entity.SysConfig, error) {
	var list []*entity.SysConfig
	if err := r.db.WithContext(ctx).Where("config_group = ? AND is_enabled = ?", group, true).Order("sort_order DESC").Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}

func (r *sysConfigRepository) ListAll(ctx context.Context) ([]*entity.SysConfig, error) {
	var list []*entity.SysConfig
	if err := r.db.WithContext(ctx).Order("config_group ASC, sort_order ASC, id ASC").Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}

func (r *sysConfigRepository) Create(ctx context.Context, cfg *entity.SysConfig) error {
	return r.db.WithContext(ctx).Create(cfg).Error
}

func (r *sysConfigRepository) Update(ctx context.Context, cfg *entity.SysConfig) error {
	return r.db.WithContext(ctx).Save(cfg).Error
}

func (r *sysConfigRepository) Delete(ctx context.Context, id int64) error {
	return r.db.WithContext(ctx).Delete(&entity.SysConfig{}, id).Error
}
