package repository

import (
	"cn.meow/meowtv/internal/model/entity"

	"gorm.io/gorm"
)

// LocalVideoRepository 本地视频数据层
type LocalVideoRepository struct {
	db *gorm.DB
}

// NewLocalVideoRepository 创建本地视频 Repository
func NewLocalVideoRepository(db *gorm.DB) *LocalVideoRepository {
	return &LocalVideoRepository{db: db}
}

// BatchCreate 批量创建本地视频记录（先清空再插入）
func (r *LocalVideoRepository) BatchCreate(videos []entity.LocalVideo) error {
	if len(videos) == 0 {
		return nil
	}
	// 先清空旧数据
	if err := r.db.Where("1 = 1").Delete(&entity.LocalVideo{}).Error; err != nil {
		return err
	}
	return r.db.CreateInBatches(videos, 100).Error
}

// GetByID 根据 vod_id 获取单个本地视频
func (r *LocalVideoRepository) GetByID(vodID int64) (*entity.LocalVideo, error) {
	var video entity.LocalVideo
	if err := r.db.Where("vod_id = ?", vodID).First(&video).Error; err != nil {
		return nil, err
	}
	return &video, nil
}

// SearchByKeyword 按关键词模糊搜索
func (r *LocalVideoRepository) SearchByKeyword(keyword string) ([]entity.LocalVideo, error) {
	var videos []entity.LocalVideo
	q := r.db.Model(&entity.LocalVideo{})
	if keyword != "" {
		// 搜索 vod_name 和 vod_class 字段
		like := "%" + keyword + "%"
		q = q.Where("vod_name LIKE ? OR vod_class LIKE ?", like, like)
	}
	err := q.Order("vod_id ASC").Find(&videos).Error
	return videos, err
}

// ListAll 获取全部本地视频（按 vod_id 升序）
func (r *LocalVideoRepository) ListAll() ([]entity.LocalVideo, error) {
	var videos []entity.LocalVideo
	err := r.db.Order("vod_id ASC").Find(&videos).Error
	return videos, err
}

// ListByType 按类型（电影/剧集）获取本地视频
// typeFilter 对应豆瓣的 type 参数：movie / tv
// 当按类型 LIKE 过滤后结果为空时（demo 数据文件夹命名不匹配），回退返回全部数据，避免首页空白
func (r *LocalVideoRepository) ListByType(typeFilter string) ([]entity.LocalVideo, error) {
	var videos []entity.LocalVideo
	q := r.db.Model(&entity.LocalVideo{})
	if typeFilter == "movie" {
		q = q.Where("vod_class LIKE ? OR vod_class LIKE ?", "%电影%", "%movie%")
	} else if typeFilter == "tv" {
		q = q.Where("vod_class LIKE ? OR vod_class LIKE ?", "%剧%", "%tv%")
	}
	if err := q.Order("vod_id ASC").Find(&videos).Error; err != nil {
		return nil, err
	}
	// 回退：类型过滤无命中时返回全部数据
	if len(videos) == 0 {
		return r.ListAll()
	}
	return videos, nil
}

// Paginate 分页查询本地视频
func (r *LocalVideoRepository) Paginate(page, pageSize int, keyword string) ([]entity.LocalVideo, int64, error) {
	var videos []entity.LocalVideo
	var total int64

	q := r.db.Model(&entity.LocalVideo{})
	if keyword != "" {
		like := "%" + keyword + "%"
		q = q.Where("vod_name LIKE ? OR vod_class LIKE ?", like, like)
	}

	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	offset := (page - 1) * pageSize
	err := q.Order("vod_id ASC").Offset(offset).Limit(pageSize).Find(&videos).Error
	return videos, total, err
}

// ClearAll 清空所有本地视频记录
func (r *LocalVideoRepository) ClearAll() error {
	return r.db.Where("1 = 1").Delete(&entity.LocalVideo{}).Error
}
