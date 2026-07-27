package handler

import (
	"fmt"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// UserDataHandler 用户数据接口（搜索历史 + 播放历史 + 收藏）
type UserDataHandler struct {
	searchHistoryService *service.SearchHistoryService
	playHistoryService   *service.PlayHistoryService
	favoriteService      *service.FavoriteService
	streamService        *service.StreamService
}

// NewUserDataHandler 创建用户数据 Handler
func NewUserDataHandler(
	searchHistoryService *service.SearchHistoryService,
	playHistoryService *service.PlayHistoryService,
	favoriteService *service.FavoriteService,
	streamService *service.StreamService,
) *UserDataHandler {
	return &UserDataHandler{
		searchHistoryService: searchHistoryService,
		playHistoryService:   playHistoryService,
		favoriteService:      favoriteService,
		streamService:        streamService,
	}
}

// ── 搜索历史 ──────────────────────────────────────────────────────────────

// SearchHistoryList 获取搜索历史列表
func (h *UserDataHandler) SearchHistoryList(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.SearchHistoryListReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	items, err := h.searchHistoryService.List(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, items)
}

// SearchHistoryAdd 新增/更新搜索记录
func (h *UserDataHandler) SearchHistoryAdd(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.SearchHistoryAddReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	item, err := h.searchHistoryService.Add(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, item)
}

// SearchHistoryDelete 删除单条搜索记录
func (h *UserDataHandler) SearchHistoryDelete(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.SearchHistoryDeleteReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if err := h.searchHistoryService.Delete(userID, &req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// SearchHistoryClear 清空搜索历史
func (h *UserDataHandler) SearchHistoryClear(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	if err := h.searchHistoryService.Clear(userID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// ── 播放历史 ──────────────────────────────────────────────────────────────

// PlayHistoryGet 查询单条播放记录
func (h *UserDataHandler) PlayHistoryGet(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.PlayHistoryGetReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	item, err := h.playHistoryService.Get(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, item)
}

// PlayHistoryList 获取播放历史列表
func (h *UserDataHandler) PlayHistoryList(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.PlayHistoryListReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	resp, err := h.playHistoryService.List(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// PlayHistoryUpsert 新增/更新播放记录
func (h *UserDataHandler) PlayHistoryUpsert(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.PlayHistoryUpsertReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	item, err := h.playHistoryService.Upsert(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, item)
}

// PlayHistoryProgress 仅更新播放进度（高频调用）
func (h *UserDataHandler) PlayHistoryProgress(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.PlayHistoryProgressReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	// 1. 持久化播放历史
	if err := h.playHistoryService.UpdateProgress(userID, &req); err != nil {
		return err
	}

	// 2. 如果有 session 字段，更新流调度进度
	if req.Session != "" && h.streamService != nil {
		// 从 PlayHistoryProgressReq 中提取 epName（用于自动保存）
		epName := req.EpName
		if epName == "" {
			epName = fmt.Sprintf("第%d集", req.EpIndex+1)
		}
		_ = h.streamService.UpdateProgress(
			userID,
			req.Session,
			req.CurrentIndex,
			req.BufferedAhead,
			req.VodID,
			req.VodName,
			req.VodPic,
			req.ResourceDomain,
			req.ResourceName,
			req.GroupKey,
			req.SourceIndex,
			req.EpIndex,
			epName,
		)
	}

	return response.OK(c, nil)
}

// PlayHistoryDelete 删除单条播放记录
func (h *UserDataHandler) PlayHistoryDelete(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.PlayHistoryDeleteReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if err := h.playHistoryService.Delete(userID, &req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// PlayHistoryClear 清空播放历史
func (h *UserDataHandler) PlayHistoryClear(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	if err := h.playHistoryService.Clear(userID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// ── 收藏 ──────────────────────────────────────────────────────────────────

// FavoritesList 获取收藏列表
func (h *UserDataHandler) FavoritesList(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.FavoriteListReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	resp, err := h.favoriteService.List(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// FavoritesAdd 添加收藏
func (h *UserDataHandler) FavoritesAdd(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.FavoriteAddReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	item, err := h.favoriteService.Add(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, item)
}

// FavoritesRemove 取消收藏
func (h *UserDataHandler) FavoritesRemove(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.FavoriteRemoveReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	if err := h.favoriteService.Remove(userID, &req); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// FavoritesToggle 切换收藏状态
func (h *UserDataHandler) FavoritesToggle(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.FavoriteAddReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	resp, err := h.favoriteService.Toggle(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}

// FavoritesClear 清空收藏
func (h *UserDataHandler) FavoritesClear(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	if err := h.favoriteService.Clear(userID); err != nil {
		return err
	}
	return response.OK(c, nil)
}

// FavoritesCheck 检查是否已收藏
func (h *UserDataHandler) FavoritesCheck(c echo.Context) error {
	userID := c.Get(middleware.UserIDKey).(int64)

	var req request.FavoriteCheckReq
	if err := c.Bind(&req); err != nil {
		return err
	}
	if err := c.Validate(&req); err != nil {
		return err
	}

	resp, err := h.favoriteService.Check(userID, &req)
	if err != nil {
		return err
	}
	return response.OK(c, resp)
}
