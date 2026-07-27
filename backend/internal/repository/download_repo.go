package repository

import (
	"cn.meow/meowtv/internal/model/entity"

	"gorm.io/gorm"
)

// DownloadRepository 下载任务数据层
type DownloadRepository struct {
	db *gorm.DB
}

// NewDownloadRepository 创建下载任务 Repository
func NewDownloadRepository(db *gorm.DB) *DownloadRepository {
	return &DownloadRepository{db: db}
}

// Create 创建下载任务
func (r *DownloadRepository) Create(task *entity.DownloadTask) (*entity.DownloadTask, error) {
	if err := r.db.Create(task).Error; err != nil {
		return nil, err
	}
	return task, nil
}

// GetByID 根据 ID 获取任务
func (r *DownloadRepository) GetByID(id int64) (*entity.DownloadTask, error) {
	var task entity.DownloadTask
	if err := r.db.Where("id = ?", id).First(&task).Error; err != nil {
		return nil, err
	}
	return &task, nil
}

// List 获取用户下载任务列表（按 created_at 降序，支持分页和状态过滤）
func (r *DownloadRepository) List(userID int64, status *int, limit, offset int) ([]entity.DownloadTask, error) {
	var tasks []entity.DownloadTask
	q := r.db.Where("user_id = ?", userID)
	if status != nil {
		q = q.Where("status = ?", *status)
	}
	err := q.Order("created_at DESC").Offset(offset).Limit(limit).Find(&tasks).Error
	return tasks, err
}

// Count 统计用户下载任务数
func (r *DownloadRepository) Count(userID int64, status *int) (int64, error) {
	var count int64
	q := r.db.Model(&entity.DownloadTask{}).Where("user_id = ?", userID)
	if status != nil {
		q = q.Where("status = ?", *status)
	}
	err := q.Count(&count).Error
	return count, err
}

// Update 更新下载任务
func (r *DownloadRepository) Update(task *entity.DownloadTask) error {
	return r.db.Save(task).Error
}

// UpdateStatus 更新任务状态
func (r *DownloadRepository) UpdateStatus(id int64, status entity.DownloadStatus, errMsg string) error {
	updates := map[string]interface{}{
		"status":    status,
		"error_msg": errMsg,
	}
	return r.db.Model(&entity.DownloadTask{}).Where("id = ?", id).Updates(updates).Error
}

// UpdateProgress 更新下载进度
func (r *DownloadRepository) UpdateProgress(id int64, downloadedSegments int, progress float64) error {
	return r.db.Model(&entity.DownloadTask{}).Where("id = ?", id).Updates(map[string]interface{}{
		"downloaded_segments": downloadedSegments,
		"progress":            progress,
	}).Error
}

// UpdateCompleted 标记任务完成
func (r *DownloadRepository) UpdateCompleted(id int64, filePath string, fileSize int64) error {
	return r.db.Model(&entity.DownloadTask{}).Where("id = ?", id).Updates(map[string]interface{}{
		"status":    entity.DownloadStatusCompleted,
		"progress":  100.0,
		"file_path": filePath,
		"file_size": fileSize,
	}).Error
}

// Delete 删除下载任务
func (r *DownloadRepository) Delete(id int64) error {
	return r.db.Where("id = ?", id).Delete(&entity.DownloadTask{}).Error
}

// FindExisting 查找用户已存在的下载任务（同 m3u8_url 且状态非终态）
func (r *DownloadRepository) FindExisting(userID int64, m3u8URL string) (*entity.DownloadTask, error) {
	var task entity.DownloadTask
	err := r.db.Where("user_id = ? AND m3u8_url = ? AND status NOT IN ?",
		userID, m3u8URL,
		[]entity.DownloadStatus{entity.DownloadStatusFailed, entity.DownloadStatusCancelled},
	).First(&task).Error
	if err != nil {
		return nil, err
	}
	return &task, nil
}

// FindCompleted 查找用户已完成的下载任务（用于本地视频优先播放检查）
func (r *DownloadRepository) FindCompleted(userID int64, resourceDomain string, vodID int64, sourceIndex, epIndex int) (*entity.DownloadTask, error) {
	var task entity.DownloadTask
	err := r.db.Where("user_id = ? AND resource_domain = ? AND vod_id = ? AND source_index = ? AND ep_index = ? AND status = ?",
		userID, resourceDomain, vodID, sourceIndex, epIndex, entity.DownloadStatusCompleted,
	).First(&task).Error
	if err != nil {
		return nil, err
	}
	return &task, nil
}

// FindByUserAndURL 查找用户同 m3u8_url 的下载任务（任意状态，取最新一条）
func (r *DownloadRepository) FindByUserAndURL(userID int64, m3u8URL string) (*entity.DownloadTask, error) {
	var task entity.DownloadTask
	err := r.db.Where("user_id = ? AND m3u8_url = ?", userID, m3u8URL).
		Order("created_at DESC").
		First(&task).Error
	if err != nil {
		return nil, err
	}
	return &task, nil
}

// ResetForRetry 重置任务为排队状态（用于重新下载）
func (r *DownloadRepository) ResetForRetry(id int64) error {
	return r.db.Model(&entity.DownloadTask{}).Where("id = ?", id).Updates(map[string]interface{}{
		"status":              entity.DownloadStatusQueued,
		"progress":            0,
		"downloaded_segments": 0,
		"error_msg":           "",
	}).Error
}

// UpdateFilePath 更新任务文件路径（用于即时 remux 后更新 DB）
func (r *DownloadRepository) UpdateFilePath(id int64, filePath string) error {
	return r.db.Model(&entity.DownloadTask{}).Where("id = ?", id).Update("file_path", filePath).Error
}

// ListAll 管理端查看所有用户任务
func (r *DownloadRepository) ListAll(status *int, limit, offset int) ([]entity.DownloadTask, error) {
	var tasks []entity.DownloadTask
	q := r.db.Model(&entity.DownloadTask{})
	if status != nil {
		q = q.Where("status = ?", *status)
	}
	err := q.Order("created_at DESC").Offset(offset).Limit(limit).Find(&tasks).Error
	return tasks, err
}

// CountAll 管理端统计所有任务数
func (r *DownloadRepository) CountAll(status *int) (int64, error) {
	var count int64
	q := r.db.Model(&entity.DownloadTask{})
	if status != nil {
		q = q.Where("status = ?", *status)
	}
	err := q.Count(&count).Error
	return count, err
}
