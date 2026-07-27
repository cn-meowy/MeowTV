package repository

import (
	"cn.meow/meowtv/internal/model/entity"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// SearchHistoryRepository 搜索记录数据层
type SearchHistoryRepository struct {
	db *gorm.DB
}

// NewSearchHistoryRepository 创建搜索记录 Repository
func NewSearchHistoryRepository(db *gorm.DB) *SearchHistoryRepository {
	return &SearchHistoryRepository{db: db}
}

// List 获取用户搜索历史（按 updated_at 降序）
func (r *SearchHistoryRepository) List(userID int64, limit int) ([]entity.SearchHistory, error) {
	var records []entity.SearchHistory
	err := r.db.Where("user_id = ?", userID).
		Order("updated_at DESC").
		Limit(limit).
		Find(&records).Error
	return records, err
}

// Add 新增或更新搜索记录（同用户同关键词更新 updated_at）
func (r *SearchHistoryRepository) Add(userID int64, keyword string) (*entity.SearchHistory, error) {
	record := entity.SearchHistory{
		UserID:  userID,
		Keyword: keyword,
	}
	// 使用 ON CONFLICT 避免竞态条件导致的唯一约束冲突
	result := r.db.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "user_id"}, {Name: "keyword"}},
		DoUpdates: clause.AssignmentColumns([]string{"updated_at", "deleted_at"}), // deleted_at: 清除软删除状态，使记录重新可见
	}).Create(&record)
	if result.Error != nil {
		return nil, result.Error
	}
	// upsert 后直接返回，record 中的 UserID/Keyword 已正确，UpdatedAt 由数据库更新
	// 注意：如果是 UPDATE 操作，record.ID 已在冲突时被正确赋值，无需重新查询
	return &record, nil
}

// Delete 删除单条搜索记录
func (r *SearchHistoryRepository) Delete(userID, id int64) error {
	return r.db.Where("user_id = ? AND id = ?", userID, id).Delete(&entity.SearchHistory{}).Error
}

// Clear 清空用户搜索历史
func (r *SearchHistoryRepository) Clear(userID int64) error {
	return r.db.Where("user_id = ?", userID).Delete(&entity.SearchHistory{}).Error
}

// Count 统计用户搜索记录数
func (r *SearchHistoryRepository) Count(userID int64) (int64, error) {
	var count int64
	err := r.db.Model(&entity.SearchHistory{}).Where("user_id = ?", userID).Count(&count).Error
	return count, err
}

// EvictOldest 淘汰最旧的记录（保留 limit 条）
func (r *SearchHistoryRepository) EvictOldest(userID int64, keepLimit int) error {
	// 查询需要删除的 ID（超出 keepLimit 的旧记录）
	var ids []int64
	err := r.db.Model(&entity.SearchHistory{}).
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
	return r.db.Where("id IN ?", ids).Delete(&entity.SearchHistory{}).Error
}
