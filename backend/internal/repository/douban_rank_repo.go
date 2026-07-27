package repository

import (
	"context"
	"time"

	"gorm.io/gorm"

	"cn.meow/meowtv/internal/model/entity"
)

// DoubanRankRepository 影视榜单数据层接口
type DoubanRankRepository interface {
	// Upsert 插入或更新（按 rank_date + category 冲突时更新）
	Upsert(ctx context.Context, rank *entity.DoubanRank) error
	// GetByDateAndCategory 获取指定日期和分类的数据
	GetByDateAndCategory(ctx context.Context, date time.Time, category string) (*entity.DoubanRank, error)
	// GetLatestByCategory 获取指定分类的最新数据（按 rank_date DESC）
	GetLatestByCategory(ctx context.Context, category string) (*entity.DoubanRank, error)
	// CountDistinctDates 统计不同日期数
	CountDistinctDates(ctx context.Context) (int, error)
	// GetMinDate 获取最早日期
	GetMinDate(ctx context.Context) (*time.Time, error)
	// DeleteByDate 删除指定日期的全部数据
	DeleteByDate(ctx context.Context, date time.Time) error
	// HasSuccessRecord 检查指定日期是否有成功同步的记录
	HasSuccessRecord(ctx context.Context, date time.Time) (bool, error)
	// ListByDate 获取指定日期的所有分类数据
	ListByDate(ctx context.Context, date time.Time) ([]*entity.DoubanRank, error)
	// ListLatestByType 获取指定 type 最新日期的所有分类数据
	ListLatestByType(ctx context.Context, rankType string) ([]*entity.DoubanRank, error)
}

// doubanRankRepository GORM 实现
type doubanRankRepository struct {
	db *gorm.DB
}

// NewDoubanRankRepository 创建影视榜单 Repository
func NewDoubanRankRepository(db *gorm.DB) DoubanRankRepository {
	return &doubanRankRepository{db: db}
}

func (r *doubanRankRepository) Upsert(ctx context.Context, rank *entity.DoubanRank) error {
	// SQLite 使用 ON CONFLICT 实现 upsert
	result := r.db.WithContext(ctx).
		Where("rank_date = ? AND category = ?", rank.RankDate, rank.Category).
		First(&entity.DoubanRank{})

	if result.Error == gorm.ErrRecordNotFound {
		return r.db.WithContext(ctx).Create(rank).Error
	}
	if result.Error != nil {
		return result.Error
	}

	// 记录已存在，更新
	return r.db.WithContext(ctx).
		Model(&entity.DoubanRank{}).
		Where("rank_date = ? AND category = ?", rank.RankDate, rank.Category).
		Updates(map[string]interface{}{
			"type":         rank.Type,
			"tag":          rank.Tag,
			"data":         rank.Data,
			"sync_status":  rank.SyncStatus,
			"record_count": rank.RecordCount,
		}).Error
}

func (r *doubanRankRepository) GetByDateAndCategory(ctx context.Context, date time.Time, category string) (*entity.DoubanRank, error) {
	var rank entity.DoubanRank
	// rank_date 是 date 类型，需要按日期比较
	err := r.db.WithContext(ctx).
		Where("rank_date = ? AND category = ?", date.Format("2006-01-02"), category).
		First(&rank).Error
	if err != nil {
		return nil, err
	}
	return &rank, nil
}

func (r *doubanRankRepository) GetLatestByCategory(ctx context.Context, category string) (*entity.DoubanRank, error) {
	var rank entity.DoubanRank
	err := r.db.WithContext(ctx).
		Where("category = ?", category).
		Order("rank_date DESC").
		First(&rank).Error
	if err != nil {
		return nil, err
	}
	return &rank, nil
}

func (r *doubanRankRepository) CountDistinctDates(ctx context.Context) (int, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&entity.DoubanRank{}).
		Distinct("rank_date").
		Count(&count).Error
	return int(count), err
}

func (r *doubanRankRepository) GetMinDate(ctx context.Context) (*time.Time, error) {
	var rank entity.DoubanRank
	err := r.db.WithContext(ctx).
		Select("rank_date").
		Order("rank_date ASC").
		First(&rank).Error
	if err != nil {
		return nil, err
	}
	return &rank.RankDate, nil
}

func (r *doubanRankRepository) DeleteByDate(ctx context.Context, date time.Time) error {
	return r.db.WithContext(ctx).
		Where("rank_date = ?", date.Format("2006-01-02")).
		Delete(&entity.DoubanRank{}).Error
}

func (r *doubanRankRepository) HasSuccessRecord(ctx context.Context, date time.Time) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&entity.DoubanRank{}).
		Where("rank_date = ? AND sync_status = ?", date.Format("2006-01-02"), entity.SyncStatusSuccess).
		Count(&count).Error
	return count > 0, err
}

func (r *doubanRankRepository) ListByDate(ctx context.Context, date time.Time) ([]*entity.DoubanRank, error) {
	var list []*entity.DoubanRank
	err := r.db.WithContext(ctx).
		Where("rank_date = ?", date.Format("2006-01-02")).
		Find(&list).Error
	return list, err
}

func (r *doubanRankRepository) ListLatestByType(ctx context.Context, rankType string) ([]*entity.DoubanRank, error) {
	// 获取指定 type 最新日期的所有数据
	var latestDate entity.DoubanRank
	err := r.db.WithContext(ctx).
		Select("rank_date").
		Where("type = ?", rankType).
		Order("rank_date DESC").
		First(&latestDate).Error
	if err != nil {
		return nil, err
	}

	var list []*entity.DoubanRank
	err = r.db.WithContext(ctx).
		Where("rank_date = ? AND type = ?", latestDate.RankDate.Format("2006-01-02"), rankType).
		Find(&list).Error
	return list, err
}
