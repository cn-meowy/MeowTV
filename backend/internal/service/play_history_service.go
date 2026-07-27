package service

import (
	"errors"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"

	"gorm.io/gorm"
)

const maxPlayHistoryPerUser = 200

// PlayHistoryService 播放历史业务层
type PlayHistoryService struct {
	repo *repository.PlayHistoryRepository
}

// NewPlayHistoryService 创建播放历史 Service
func NewPlayHistoryService(repo *repository.PlayHistoryRepository) *PlayHistoryService {
	return &PlayHistoryService{repo: repo}
}

// Get 查询单条播放记录（记录不存在时返回 nil, nil，非错误）
func (s *PlayHistoryService) Get(userID int64, req *request.PlayHistoryGetReq) (*response.PlayHistoryItem, error) {
	record, err := s.repo.GetByVodAndEp(userID, req.VodID, req.ResourceDomain, req.EpIndex)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, errs.Wrap(err, errs.ErrInternal)
	}
	item := toPlayHistoryItem(record)
	return &item, nil
}

// List 获取播放历史列表
func (s *PlayHistoryService) List(userID int64, req *request.PlayHistoryListReq) (*response.PlayHistoryListResp, error) {
	limit := req.Limit
	if limit <= 0 {
		limit = 20
	}
	offset := req.Offset
	if offset < 0 {
		offset = 0
	}

	records, err := s.repo.List(userID, limit, offset)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	total, err := s.repo.Count(userID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	items := make([]response.PlayHistoryItem, 0, len(records))
	for _, r := range records {
		items = append(items, toPlayHistoryItem(&r))
	}

	return &response.PlayHistoryListResp{
		Total: total,
		Items: items,
	}, nil
}

// Upsert 新增/更新播放记录
func (s *PlayHistoryService) Upsert(userID int64, req *request.PlayHistoryUpsertReq) (*response.PlayHistoryItem, error) {
	record := &entity.PlayHistory{
		UserID:         userID,
		VodID:          req.VodID,
		VodName:        req.VodName,
		VodPic:         req.VodPic,
		ResourceDomain: req.ResourceDomain,
		ResourceName:   req.ResourceName,
		GroupKey:       req.GroupKey,
		SourceIndex:    req.SourceIndex,
		EpIndex:        req.EpIndex,
		EpName:         req.EpName,
		Progress:       req.Progress,
		CurrentTime:    req.CurrentTime,
		Duration:       req.Duration,
	}

	result, err := s.repo.Upsert(record)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 淘汰超出上限的旧记录
	_ = s.repo.EvictOldest(userID, maxPlayHistoryPerUser)

	item := toPlayHistoryItem(result)
	return &item, nil
}

// UpdateProgress 更新播放进度（upsert：记录不存在时自动创建）
func (s *PlayHistoryService) UpdateProgress(userID int64, req *request.PlayHistoryProgressReq) error {
	record := &entity.PlayHistory{
		UserID:         userID,
		VodID:          req.VodID,
		VodName:        req.VodName,
		VodPic:         req.VodPic,
		ResourceDomain: req.ResourceDomain,
		ResourceName:   req.ResourceName,
		GroupKey:       req.GroupKey,
		SourceIndex:    req.SourceIndex,
		EpIndex:        req.EpIndex,
		EpName:         req.EpName,
		Progress:       req.Progress,
		CurrentTime:    req.CurrentTime,
		Duration:       req.Duration,
	}
	if err := s.repo.UpdateProgress(record); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}
	return nil
}

// Delete 删除单条播放记录
func (s *PlayHistoryService) Delete(userID int64, req *request.PlayHistoryDeleteReq) error {
	if err := s.repo.Delete(userID, req.ID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}
	return nil
}

// Clear 清空播放历史
func (s *PlayHistoryService) Clear(userID int64) error {
	if err := s.repo.Clear(userID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}
	return nil
}

// toPlayHistoryItem 实体转响应
func toPlayHistoryItem(r *entity.PlayHistory) response.PlayHistoryItem {
	return response.PlayHistoryItem{
		ID:             r.ID,
		VodID:          r.VodID,
		VodName:        r.VodName,
		VodPic:         r.VodPic,
		ResourceDomain: r.ResourceDomain,
		ResourceName:   r.ResourceName,
		GroupKey:       r.GroupKey,
		SourceIndex:    r.SourceIndex,
		EpIndex:        r.EpIndex,
		EpName:         r.EpName,
		Progress:       r.Progress,
		CurrentTime:    r.CurrentTime,
		Duration:       r.Duration,
		CreatedAt:      r.CreatedAt.UnixMilli(),
		UpdatedAt:      r.UpdatedAt.UnixMilli(),
	}
}
