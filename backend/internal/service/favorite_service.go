package service

import (
	"context"
	"log/slog"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

// FavoriteService 收藏业务层
type FavoriteService struct {
	repo  *repository.FavoriteRepository
	cache cache.Cache
}

// NewFavoriteService 创建收藏 Service
func NewFavoriteService(repo *repository.FavoriteRepository, cache cache.Cache) *FavoriteService {
	return &FavoriteService{repo: repo, cache: cache}
}

// List 获取收藏列表
func (s *FavoriteService) List(userID int64, req *request.FavoriteListReq) (*response.FavoriteListResp, error) {
	limit := req.Limit
	if limit <= 0 {
		limit = 20
	}
	offset := req.Offset
	if offset < 0 {
		offset = 0
	}

	records, err := s.repo.List(userID, limit, offset, req.Keyword)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	total, err := s.repo.Count(userID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	items := make([]response.FavoriteItem, 0, len(records))
	for _, r := range records {
		items = append(items, toFavoriteItem(&r))
	}

	return &response.FavoriteListResp{
		Total: total,
		Items: items,
	}, nil
}

// Add 添加收藏
func (s *FavoriteService) Add(userID int64, req *request.FavoriteAddReq) (*response.FavoriteItem, error) {
	if err := validateFavoriteKey(req.VodID, req.ResourceDomain, req.DoubanID); err != nil {
		return nil, err
	}

	record := &entity.Favorite{
		UserID:         userID,
		VodID:          req.VodID,
		VodName:        req.VodName,
		VodPic:         req.VodPic,
		DoubanID:       req.DoubanID,
		GroupKey:       req.GroupKey,
		Site:           req.Site,
		ResourceDomain: req.ResourceDomain,
		ResourceName:   req.ResourceName,
	}

	result, err := s.repo.Add(record)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	s.clearFavoriteCheckCache(context.Background(), userID, req.VodID, req.ResourceDomain, req.DoubanID)

	item := toFavoriteItem(result)
	return &item, nil
}

// Remove 取消收藏
func (s *FavoriteService) Remove(userID int64, req *request.FavoriteRemoveReq) error {
	if err := validateFavoriteKey(req.VodID, req.ResourceDomain, req.DoubanID); err != nil {
		return err
	}

	if err := s.repo.Remove(userID, req.VodID, req.ResourceDomain, req.DoubanID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	s.clearFavoriteCheckCache(context.Background(), userID, req.VodID, req.ResourceDomain, req.DoubanID)

	return nil
}

// Toggle 切换收藏状态
func (s *FavoriteService) Toggle(userID int64, req *request.FavoriteAddReq) (*response.FavoriteCheckResp, error) {
	if err := validateFavoriteKey(req.VodID, req.ResourceDomain, req.DoubanID); err != nil {
		return nil, err
	}

	// 直接查库，不走缓存读，避免缓存与数据库不一致
	isFav, err := s.repo.IsFavorite(userID, req.VodID, req.ResourceDomain, req.DoubanID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	if isFav {
		if err := s.repo.Remove(userID, req.VodID, req.ResourceDomain, req.DoubanID); err != nil {
			return nil, errs.Wrap(err, errs.ErrInternal)
		}
		s.clearFavoriteCheckCache(context.Background(), userID, req.VodID, req.ResourceDomain, req.DoubanID)
		return &response.FavoriteCheckResp{IsFavorite: false}, nil
	}

	record := &entity.Favorite{
		UserID:         userID,
		VodID:          req.VodID,
		VodName:        req.VodName,
		VodPic:         req.VodPic,
		DoubanID:       req.DoubanID,
		GroupKey:       req.GroupKey,
		Site:           req.Site,
		ResourceDomain: req.ResourceDomain,
		ResourceName:   req.ResourceName,
	}
	if _, err := s.repo.Add(record); err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}
	s.clearFavoriteCheckCache(context.Background(), userID, req.VodID, req.ResourceDomain, req.DoubanID)
	return &response.FavoriteCheckResp{IsFavorite: true}, nil
}

// Check 检查是否已收藏
func (s *FavoriteService) Check(userID int64, req *request.FavoriteCheckReq) (*response.FavoriteCheckResp, error) {
	if err := validateFavoriteKey(req.VodID, req.ResourceDomain, req.DoubanID); err != nil {
		return nil, err
	}

	// 先查缓存
	ck := cache.KeyFavoriteCheck(userID, req.VodID, req.ResourceDomain, req.DoubanID)
	if val, err := s.cache.Get(context.Background(), ck.Key); err == nil && val != "" {
		return &response.FavoriteCheckResp{IsFavorite: val == "true"}, nil
	}

	// 缓存未命中，查库
	isFav, err := s.repo.IsFavorite(userID, req.VodID, req.ResourceDomain, req.DoubanID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 写入缓存
	val := "false"
	if isFav {
		val = "true"
	}
	_ = s.cache.Set(context.Background(), ck.Key, val, ck.TTL)

	return &response.FavoriteCheckResp{IsFavorite: isFav}, nil
}

// Clear 清空收藏
func (s *FavoriteService) Clear(userID int64) error {
	if err := s.repo.Clear(userID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// Clear 无法精确删除所有 check key（GoCache 不支持 DeleteByPattern），
	// check 缓存会在 TTL 到期后自动失效，最大不一致窗口为 30 分钟。
	return nil
}

// validateFavoriteKey 校验收藏标识：vod_id+resource_domain 或 douban_id 至少有一组
func validateFavoriteKey(vodID int64, resourceDomain, doubanID string) error {
	if vodID > 0 && resourceDomain != "" {
		return nil
	}
	if doubanID != "" {
		return nil
	}
	return errs.WithMsg("vod_id+resource_domain 或 douban_id 至少需要提供一组", errs.ErrBadRequest)
}

// toFavoriteItem 实体转响应
func toFavoriteItem(r *entity.Favorite) response.FavoriteItem {
	return response.FavoriteItem{
		ID:             r.ID,
		VodID:          r.VodID,
		VodName:        r.VodName,
		VodPic:         r.VodPic,
		DoubanID:       r.DoubanID,
		GroupKey:       r.GroupKey,
		Site:           r.Site,
		ResourceDomain: r.ResourceDomain,
		ResourceName:   r.ResourceName,
		CreatedAt:      r.CreatedAt.UnixMilli(),
	}
}

// clearFavoriteCheckCache 清除收藏状态缓存
func (s *FavoriteService) clearFavoriteCheckCache(ctx context.Context, userID, vodID int64, resourceDomain, doubanID string) {
	ck := cache.KeyFavoriteCheck(userID, vodID, resourceDomain, doubanID)
	if err := s.cache.Delete(ctx, ck.Key); err != nil {
		slog.Error("failed to clear favorite check cache", "user_id", userID, "error", err)
	}
}
