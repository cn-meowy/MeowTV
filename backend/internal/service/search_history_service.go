package service

import (
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

const maxSearchHistoryPerUser = 50

// SearchHistoryService 搜索记录业务层
type SearchHistoryService struct {
	repo *repository.SearchHistoryRepository
}

// NewSearchHistoryService 创建搜索记录 Service
func NewSearchHistoryService(repo *repository.SearchHistoryRepository) *SearchHistoryService {
	return &SearchHistoryService{repo: repo}
}

// List 获取搜索历史列表
func (s *SearchHistoryService) List(userID int64, req *request.SearchHistoryListReq) ([]response.SearchHistoryItem, error) {
	limit := req.Limit
	if limit <= 0 {
		limit = 20
	}

	records, err := s.repo.List(userID, limit)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	items := make([]response.SearchHistoryItem, 0, len(records))
	for _, r := range records {
		items = append(items, response.SearchHistoryItem{
			ID:        r.ID,
			Keyword:   r.Keyword,
			UpdatedAt: r.UpdatedAt.UnixMilli(),
		})
	}
	return items, nil
}

// Add 新增/更新搜索记录
func (s *SearchHistoryService) Add(userID int64, req *request.SearchHistoryAddReq) (*response.SearchHistoryItem, error) {
	record, err := s.repo.Add(userID, req.Keyword)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 淘汰超出上限的旧记录
	_ = s.repo.EvictOldest(userID, maxSearchHistoryPerUser)

	return &response.SearchHistoryItem{
		ID:        record.ID,
		Keyword:   record.Keyword,
		UpdatedAt: record.UpdatedAt.UnixMilli(),
	}, nil
}

// Delete 删除单条搜索记录
func (s *SearchHistoryService) Delete(userID int64, req *request.SearchHistoryDeleteReq) error {
	if err := s.repo.Delete(userID, req.ID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}
	return nil
}

// Clear 清空搜索历史
func (s *SearchHistoryService) Clear(userID int64) error {
	if err := s.repo.Clear(userID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}
	return nil
}

// toSearchHistoryItem 辅助函数
func toSearchHistoryItem(r *entity.SearchHistory) response.SearchHistoryItem {
	return response.SearchHistoryItem{
		ID:        r.ID,
		Keyword:   r.Keyword,
		UpdatedAt: r.UpdatedAt.UnixMilli(),
	}
}
