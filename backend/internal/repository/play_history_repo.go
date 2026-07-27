package repository

import (
	"cn.meow/meowtv/internal/model/entity"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// PlayHistoryRepository 播放历史数据层
type PlayHistoryRepository struct {
	db *gorm.DB
}

// NewPlayHistoryRepository 创建播放历史 Repository
func NewPlayHistoryRepository(db *gorm.DB) *PlayHistoryRepository {
	return &PlayHistoryRepository{db: db}
}

// List 获取用户播放历史（按 updated_at 降序，支持分页）
func (r *PlayHistoryRepository) List(userID int64, limit, offset int) ([]entity.PlayHistory, error) {
	var records []entity.PlayHistory
	err := r.db.Where("user_id = ?", userID).
		Order("updated_at DESC").
		Offset(offset).
		Limit(limit).
		Find(&records).Error
	return records, err
}

// Count 统计用户播放历史数
func (r *PlayHistoryRepository) Count(userID int64) (int64, error) {
	var count int64
	err := r.db.Model(&entity.PlayHistory{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

// GetByVodAndEp 根据用户ID、视频ID、资源域名和集索引查询单条播放记录
func (r *PlayHistoryRepository) GetByVodAndEp(userID int64, vodID int64, resourceDomain string, epIndex int) (*entity.PlayHistory, error) {
	var record entity.PlayHistory
	err := r.db.Where("user_id = ? AND vod_id = ? AND resource_domain = ? AND ep_index = ?",
		userID, vodID, resourceDomain, epIndex).First(&record).Error
	if err != nil {
		return nil, err
	}
	return &record, nil
}

// Upsert 新增或更新播放记录（原子 upsert，避免并发下 UNIQUE 冲突）
func (r *PlayHistoryRepository) Upsert(record *entity.PlayHistory) (*entity.PlayHistory, error) {
	result := r.db.Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "user_id"},
			{Name: "vod_id"},
			{Name: "resource_domain"},
			{Name: "ep_index"},
		},
		DoUpdates: clause.AssignmentColumns([]string{
			"vod_name", "vod_pic", "resource_name", "group_key",
			"source_index", "ep_index", "ep_name",
			// progress, current_time, duration 由 UpdateProgress 专门管理，
			// 不在 Upsert 中更新，避免 Go 零值覆写已有的播放进度
			"updated_at",
			"deleted_at", // 清除软删除状态，使记录重新可见
		}),
	}).Create(record)

	if result.Error != nil {
		return nil, result.Error
	}

	// 重新加载以获取完整的自动生成字段（使用 Unscoped 避免软删除记录查不到）
	var updated entity.PlayHistory
	if err := r.db.Unscoped().Where("user_id = ? AND vod_id = ? AND resource_domain = ? AND ep_index = ?",
		record.UserID, record.VodID, record.ResourceDomain, record.EpIndex).
		First(&updated).Error; err != nil {
		return nil, err
	}
	return &updated, nil
}

// UpdateProgress 更新播放进度（原子 upsert：记录不存在时自动创建，避免并发冲突）
func (r *PlayHistoryRepository) UpdateProgress(record *entity.PlayHistory) error {
	result := r.db.Clauses(clause.OnConflict{
		Columns: []clause.Column{
			{Name: "user_id"},
			{Name: "vod_id"},
			{Name: "resource_domain"},
			{Name: "ep_index"},
		},
		DoUpdates: clause.AssignmentColumns([]string{
			"vod_name", "vod_pic", "resource_name",
			"progress", "current_time", "duration",
			"source_index", "ep_index", "ep_name",
			"updated_at",
			"deleted_at", // 清除软删除状态，使记录重新可见
		}),
	}).Create(record)

	return result.Error
}

// Delete 删除单条播放记录
func (r *PlayHistoryRepository) Delete(userID, id int64) error {
	return r.db.Where("user_id = ? AND id = ?", userID, id).Delete(&entity.PlayHistory{}).Error
}

// Clear 清空用户播放历史
func (r *PlayHistoryRepository) Clear(userID int64) error {
	return r.db.Where("user_id = ?", userID).Delete(&entity.PlayHistory{}).Error
}

// EvictOldest 淘汰最旧的记录（保留 keepLimit 条）
func (r *PlayHistoryRepository) EvictOldest(userID int64, keepLimit int) error {
	var ids []int64
	err := r.db.Model(&entity.PlayHistory{}).
		Where("user_id = ?", userID).
		Order("updated_at DESC").
		Offset(keepLimit).
		Pluck("id", &ids).Error
	if err != nil {
		return err
	}
	if len(ids) == 0 {
		return nil
	}
	return r.db.Where("id IN ?", ids).Delete(&entity.PlayHistory{}).Error
}
