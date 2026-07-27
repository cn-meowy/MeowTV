package repository

import (
	"cn.meow/meowtv/internal/model/entity"
	"strings"

	"gorm.io/gorm"
)

// FavoriteRepository 收藏数据层
type FavoriteRepository struct {
	db *gorm.DB
}

// NewFavoriteRepository 创建收藏 Repository
func NewFavoriteRepository(db *gorm.DB) *FavoriteRepository {
	return &FavoriteRepository{db: db}
}

// List 获取用户收藏列表（按 created_at 降序，支持分页和关键词搜索）
func (r *FavoriteRepository) List(userID int64, limit, offset int, keyword string) ([]entity.Favorite, error) {
	var records []entity.Favorite
	q := r.db.Where("user_id = ?", userID)
	if keyword != "" {
		q = q.Where("vod_name LIKE ?", "%"+keyword+"%")
	}
	err := q.Order("created_at DESC").
		Offset(offset).
		Limit(limit).
		Find(&records).Error
	return records, err
}

// Count 统计用户收藏数
func (r *FavoriteRepository) Count(userID int64) (int64, error) {
	var count int64
	err := r.db.Model(&entity.Favorite{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

// Add 添加收藏
func (r *FavoriteRepository) Add(record *entity.Favorite) (*entity.Favorite, error) {
	// 检查是否已存在（包含软删除记录，避免唯一约束冲突）
	var existing entity.Favorite
	result := r.db.Unscoped().Where("user_id = ? AND vod_id = ? AND resource_domain = ? AND douban_id = ?",
		record.UserID, record.VodID, record.ResourceDomain, record.DoubanID).
		First(&existing)

	if result.Error == nil {
		if existing.DeletedAt.Valid {
			// 软删除记录存在，恢复它并更新字段
			return r.restoreAndUpdate(&existing, record)
		}
		// 未删除记录已存在，直接返回
		return &existing, nil
	}

	if result.Error != gorm.ErrRecordNotFound {
		return nil, result.Error
	}

	// 新增
	if err := r.db.Create(record).Error; err != nil {
		// 并发场景下可能两个请求同时通过上面的 First 检查，导致 Create 时唯一约束冲突
		// 此时回退为查找已有记录并返回
		if isUniqueConstraintError(err) {
			var existing entity.Favorite
			if findErr := r.db.Unscoped().Where("user_id = ? AND vod_id = ? AND resource_domain = ? AND douban_id = ?",
				record.UserID, record.VodID, record.ResourceDomain, record.DoubanID).
				First(&existing).Error; findErr != nil {
				return nil, findErr
			}
			if existing.DeletedAt.Valid {
				return r.restoreAndUpdate(&existing, record)
			}
			return &existing, nil
		}
		return nil, err
	}
	return record, nil
}

// restoreAndUpdate 恢复软删除的收藏记录并更新字段
func (r *FavoriteRepository) restoreAndUpdate(existing, record *entity.Favorite) (*entity.Favorite, error) {
	existing.VodName = record.VodName
	existing.VodPic = record.VodPic
	existing.DoubanID = record.DoubanID
	existing.GroupKey = record.GroupKey
	existing.Site = record.Site
	existing.ResourceName = record.ResourceName
	existing.DeletedAt = gorm.DeletedAt{}
	if err := r.db.Unscoped().Save(existing).Error; err != nil {
		return nil, err
	}
	return existing, nil
}

// Remove 取消收藏（硬删除，避免唯一约束冲突）
// 支持两种方式：按 (vodID, resourceDomain) 或 doubanID
func (r *FavoriteRepository) Remove(userID, vodID int64, resourceDomain, doubanID string) error {
	q := r.db.Unscoped().Where("user_id = ?", userID)
	if doubanID != "" {
		q = q.Where("douban_id = ?", doubanID)
	} else {
		q = q.Where("vod_id = ? AND resource_domain = ?", vodID, resourceDomain)
	}
	return q.Delete(&entity.Favorite{}).Error
}

// IsFavorite 检查是否已收藏
// 支持两种方式：按 (vodID, resourceDomain) 或 doubanID
func (r *FavoriteRepository) IsFavorite(userID, vodID int64, resourceDomain, doubanID string) (bool, error) {
	var count int64
	q := r.db.Model(&entity.Favorite{}).Where("user_id = ?", userID)
	if doubanID != "" {
		q = q.Where("douban_id = ?", doubanID)
	} else {
		q = q.Where("vod_id = ? AND resource_domain = ?", vodID, resourceDomain)
	}
	err := q.Count(&count).Error
	return count > 0, err
}

// Clear 清空用户收藏（硬删除，避免唯一约束冲突）
func (r *FavoriteRepository) Clear(userID int64) error {
	return r.db.Unscoped().Where("user_id = ?", userID).Delete(&entity.Favorite{}).Error
}

// isUniqueConstraintError 判断是否为 SQLite 唯一约束冲突错误
func isUniqueConstraintError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "UNIQUE constraint") ||
		strings.Contains(msg, "constraint failed")
}
