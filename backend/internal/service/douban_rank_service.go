package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/url"
	"strconv"
	"sync"
	"time"

	"github.com/robfig/cron/v3"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

const (
	configKeyRankSync = "douban_rank_sync"
)

// DoubanRankService 豆瓣榜单同步业务层
type DoubanRankService struct {
	repo      repository.DoubanRankRepository
	client    *DoubanClient
	configSvc *SysConfigService
	cache     cache.Cache
	cron      *cron.Cron
	cronEntry cron.EntryID
	mu        sync.RWMutex
}

// NewDoubanRankService 创建豆瓣榜单同步 Service
func NewDoubanRankService(
	repo repository.DoubanRankRepository,
	client *DoubanClient,
	configSvc *SysConfigService,
	cache cache.Cache,
) *DoubanRankService {
	return &DoubanRankService{
		repo:      repo,
		client:    client,
		configSvc: configSvc,
		cache:     cache,
	}
}

// StartCron 启动定时任务 + 启动时检查当日是否已同步
func (s *DoubanRankService) StartCron() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	ctx := context.Background()
	cfg := s.configSvc.GetValue(ctx, configKeyRankSync)
	if cfg == nil {
		slog.Info("douban rank sync config not found, skipping cron")
		return nil
	}

	autoSync := parseBool(cfg.Value1)
	if !autoSync {
		slog.Info("douban rank auto-sync is disabled")
		return nil
	}

	cronExpr := cfg.Value2
	if cronExpr == "" {
		cronExpr = "0 0 6 * * ?"
	}

	s.cron = cron.New(cron.WithSeconds())

	entryID, err := s.cron.AddFunc(cronExpr, func() {
		slog.Info("douban rank sync cron triggered")
		result, err := s.SyncAll(context.Background())
		if err != nil {
			slog.Error("douban rank sync cron failed", "error", err)
		} else {
			slog.Info("douban rank sync cron completed",
				"success", result.SuccessCount,
				"failed", result.FailedCount,
				"fallback", result.FallbackCount,
			)
		}
	})
	if err != nil {
		return fmt.Errorf("invalid cron expression %q: %w", cronExpr, err)
	}

	s.cronEntry = entryID
	s.cron.Start()
	slog.Info("douban rank sync cron started", "cron", cronExpr)

	// 启动时检查：当日若未同步成功过则执行一遍同步
	hasSuccess, _ := s.repo.HasSuccessRecord(ctx, today())
	if !hasSuccess {
		slog.Info("douban rank: no successful sync today, triggering initial sync")
		go func() {
			result, err := s.SyncAll(context.Background())
			if err != nil {
				slog.Error("douban rank initial sync failed", "error", err)
			} else {
				slog.Info("douban rank initial sync completed",
					"success", result.SuccessCount,
					"failed", result.FailedCount,
					"fallback", result.FallbackCount,
				)
			}
		}()
	}

	return nil
}

// StopCron 停止定时任务
func (s *DoubanRankService) StopCron() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.cron != nil {
		s.cron.Stop()
		s.cron = nil
		slog.Info("douban rank sync cron stopped")
	}
}

// RestartCron 重启定时任务（配置变更后调用）
func (s *DoubanRankService) RestartCron() error {
	s.StopCron()
	return s.StartCron()
}

// --- 核心同步逻辑 ---

// SyncResult 同步结果统计
type SyncResult struct {
	SuccessCount  int
	FailedCount   int
	FallbackCount int
	Errors        []string
}

// SyncAll 执行完整同步流程（Tags -> 榜单 -> 清理）
func (s *DoubanRankService) SyncAll(ctx context.Context) (*SyncResult, error) {
	result := &SyncResult{}

	// 1. 同步 Tags
	tagTypes := []struct {
		typ string
		cat string
	}{
		{"movie", "movie_tags"},
		{"tv", "tv_tags"},
	}

	for _, tt := range tagTypes {
		s.rateLimitWait(ctx)

		query := url.Values{}
		query.Set("type", tt.typ)

		data, err := s.client.FetchJSON(ctx, "/j/search_tags", query.Encode())
		if err != nil {
			slog.Warn("failed to sync tags", "type", tt.typ, "error", err)
			result.FailedCount++
			result.Errors = append(result.Errors, fmt.Sprintf("tags %s: %v", tt.typ, err))
			continue
		}

		recordCount := countSubjectsInJSON(data)
		rank := &entity.DoubanRank{
			RankDate:    today(),
			Category:    tt.cat,
			Type:        tt.typ,
			Tag:         "",
			Data:        data,
			SyncStatus:  entity.SyncStatusSuccess,
			RecordCount: recordCount,
		}

		if err := s.repo.Upsert(ctx, rank); err != nil {
			slog.Error("failed to save tags", "category", tt.cat, "error", err)
			result.Errors = append(result.Errors, fmt.Sprintf("save tags %s: %v", tt.typ, err))
		} else {
			result.SuccessCount++
			slog.Info("tags synced", "type", tt.typ, "records", recordCount)
		}
	}

	// 2. 根据 Tags 同步榜单
	s.syncSubjects(ctx, result)

	// 3. 清理超2日数据
	s.CleanupOldRecords(ctx)

	return result, nil
}

// syncSubjects 根据 Tags 同步榜单数据
func (s *DoubanRankService) syncSubjects(ctx context.Context, result *SyncResult) {
	tagTypes := []struct {
		typ string
		cat string
	}{
		{"movie", "movie_tags"},
		{"tv", "tv_tags"},
	}

	for _, tt := range tagTypes {
		tags, err := s.parseTagsFromLocal(ctx, tt.cat)
		if err != nil || len(tags) == 0 {
			slog.Warn("no tags found for type, skipping subjects sync", "type", tt.typ, "error", err)
			continue
		}

		slog.Info("syncing subjects for tags", "type", tt.typ, "tag_count", len(tags))

		for _, tag := range tags {
			s.rateLimitWait(ctx)

			category := fmt.Sprintf("%s_%s", tt.typ, tag)
			query := url.Values{}
			query.Set("type", tt.typ)
			query.Set("tag", tag)

			pageLimit := s.configSvc.GetInt(ctx, configKeyRankSync, 5)
			if pageLimit <= 0 {
				pageLimit = 50
			}
			query.Set("page_limit", strconv.Itoa(pageLimit))
			query.Set("page_start", "0")

			// 不传 sort 参数
			data, err := s.client.FetchJSON(ctx, "/j/search_subjects", query.Encode())
			if err != nil {
				slog.Warn("failed to sync subjects", "type", tt.typ, "tag", tag, "error", err)

				// 降级：查找本地历史数据
				latest, findErr := s.repo.GetLatestByCategory(ctx, category)
				if findErr == nil && latest != nil {
					fallbackRank := &entity.DoubanRank{
						RankDate:    today(),
						Category:    category,
						Type:        tt.typ,
						Tag:         tag,
						Data:        latest.Data,
						SyncStatus:  entity.SyncStatusFallback,
						RecordCount: latest.RecordCount,
					}
					if upErr := s.repo.Upsert(ctx, fallbackRank); upErr != nil {
						slog.Error("failed to save fallback data", "category", category, "error", upErr)
					} else {
						result.FallbackCount++
						slog.Info("using fallback data", "category", category, "fallback_date", latest.RankDate.Format("2006-01-02"))
					}
				} else {
					// 无历史数据，记录 failed
					failedRank := &entity.DoubanRank{
						RankDate:    today(),
						Category:    category,
						Type:        tt.typ,
						Tag:         tag,
						Data:        "{}",
						SyncStatus:  entity.SyncStatusFailed,
						RecordCount: 0,
					}
					_ = s.repo.Upsert(ctx, failedRank)
					result.FailedCount++
					result.Errors = append(result.Errors, fmt.Sprintf("subjects %s/%s: %v", tt.typ, tag, err))
				}
				continue
			}

			recordCount := countSubjectsInJSON(data)
			rank := &entity.DoubanRank{
				RankDate:    today(),
				Category:    category,
				Type:        tt.typ,
				Tag:         tag,
				Data:        data,
				SyncStatus:  entity.SyncStatusSuccess,
				RecordCount: recordCount,
			}

			if err := s.repo.Upsert(ctx, rank); err != nil {
				slog.Error("failed to save subjects", "category", category, "error", err)
				result.Errors = append(result.Errors, fmt.Sprintf("save subjects %s/%s: %v", tt.typ, tag, err))
			} else {
				result.SuccessCount++
				slog.Info("subjects synced", "type", tt.typ, "tag", tag, "records", recordCount)
			}
		}
	}
}

// parseTagsFromLocal 从本地数据库解析 Tags 列表
func (s *DoubanRankService) parseTagsFromLocal(ctx context.Context, category string) ([]string, error) {
	latest, err := s.repo.GetLatestByCategory(ctx, category)
	if err != nil {
		return nil, err
	}

	// 豆瓣 tags 返回格式：{"tags":[{"name":"热门","url":"..."}, ...]}
	var tagsResp struct {
		Tags []string `json:"tags"`
	}

	if err := json.Unmarshal([]byte(latest.Data), &tagsResp); err != nil {
		return nil, fmt.Errorf("failed to parse tags JSON: %w", err)
	}

	var tags []string
	for _, t := range tagsResp.Tags {
		if t != "" {
			tags = append(tags, t)
		}
	}
	return tags, nil
}

// --- 前端请求（本地优先 + 降级） ---

// GetSubjects 前端获取榜单（本地优先 -> 历史 -> 实时兜底）
func (s *DoubanRankService) GetSubjects(ctx context.Context, rankType, tag string, pageLimit, pageStart int) (string, error) {
	category := fmt.Sprintf("%s_%s", rankType, tag)

	// 1. 本地今日数据
	todayRank, err := s.repo.GetByDateAndCategory(ctx, today(), category)
	if err == nil && todayRank != nil && todayRank.SyncStatus != entity.SyncStatusFailed {
		return sliceSubjectsJSON(todayRank.Data, pageLimit, pageStart), nil
	}

	// 2. 本地历史数据
	latest, err := s.repo.GetLatestByCategory(ctx, category)
	if err == nil && latest != nil && latest.SyncStatus != entity.SyncStatusFailed {
		slog.Info("using historical rank data", "category", category, "date", latest.RankDate.Format("2006-01-02"))
		return sliceSubjectsJSON(latest.Data, pageLimit, pageStart), nil
	}

	// 3. 实时请求豆瓣 API 兜底
	query := url.Values{}
	query.Set("type", rankType)
	query.Set("tag", tag)
	limit := pageLimit
	if limit <= 0 {
		limit = s.configSvc.GetInt(ctx, configKeyRankSync, 5)
		if limit <= 0 {
			limit = 50
		}
	}
	query.Set("page_limit", strconv.Itoa(limit))
	query.Set("page_start", strconv.Itoa(pageStart))

	return s.client.FetchJSON(ctx, "/j/search_subjects", query.Encode())
}

// sliceSubjectsJSON 对豆瓣 subjects JSON 做分页切片
// 输入格式: {"subjects": [...], "total": N, ...}
// 输出格式: {"subjects": [切片后数组], "total": N, ...}  total 保持原始值
func sliceSubjectsJSON(data string, pageLimit, pageStart int) string {
	if pageLimit <= 0 {
		pageLimit = 20
	}
	if pageStart < 0 {
		pageStart = 0
	}

	var raw map[string]json.RawMessage
	if err := json.Unmarshal([]byte(data), &raw); err != nil {
		return data // 解析失败，返回原始数据
	}

	subjectsRaw, ok := raw["subjects"]
	if !ok {
		return data // 无 subjects 字段，返回原始数据
	}

	var subjects []json.RawMessage
	if err := json.Unmarshal(subjectsRaw, &subjects); err != nil {
		return data // subjects 不是数组，返回原始数据
	}

	// 计算切片范围
	total := len(subjects)
	if pageStart >= total {
		pageStart = total
	}
	end := pageStart + pageLimit
	if end > total {
		end = total
	}

	// 切片
	sliced := subjects[pageStart:end]

	// 重新序列化 subjects
	slicedRaw, err := json.Marshal(sliced)
	if err != nil {
		return data
	}

	// 替换 subjects 字段，保留 total 等其他字段
	raw["subjects"] = json.RawMessage(slicedRaw)

	result, err := json.Marshal(raw)
	if err != nil {
		return data
	}
	return string(result)
}

// GetTags 前端获取 Tags（本地优先 -> 历史 -> 实时兜底）
func (s *DoubanRankService) GetTags(ctx context.Context, rankType string) (string, error) {
	category := fmt.Sprintf("%s_tags", rankType)

	// 1. 本地今日数据
	todayRank, err := s.repo.GetByDateAndCategory(ctx, today(), category)
	if err == nil && todayRank != nil && todayRank.SyncStatus != entity.SyncStatusFailed {
		return todayRank.Data, nil
	}

	// 2. 本地历史数据
	latest, err := s.repo.GetLatestByCategory(ctx, category)
	if err == nil && latest != nil && latest.SyncStatus != entity.SyncStatusFailed {
		slog.Info("using historical tags data", "category", category, "date", latest.RankDate.Format("2006-01-02"))
		return latest.Data, nil
	}

	// 3. 实时请求豆瓣 API 兜底
	query := url.Values{}
	query.Set("type", rankType)

	return s.client.FetchJSON(ctx, "/j/search_tags", query.Encode())
}

// --- 数据清理 ---

// CleanupOldRecords 清理超2日数据（按日期数判断）
func (s *DoubanRankService) CleanupOldRecords(ctx context.Context) {
	keepDays := s.configSvc.GetInt(ctx, configKeyRankSync, 3)
	if keepDays <= 0 {
		keepDays = 2
	}

	dateCount, err := s.repo.CountDistinctDates(ctx)
	if err != nil {
		slog.Error("failed to count distinct dates", "error", err)
		return
	}

	if dateCount <= keepDays {
		slog.Debug("no cleanup needed", "date_count", dateCount, "keep_days", keepDays)
		return
	}

	minDate, err := s.repo.GetMinDate(ctx)
	if err != nil {
		slog.Error("failed to get min date", "error", err)
		return
	}

	if err := s.repo.DeleteByDate(ctx, *minDate); err != nil {
		slog.Error("failed to cleanup old records", "date", minDate.Format("2006-01-02"), "error", err)
	} else {
		slog.Info("cleaned up old rank data", "date", minDate.Format("2006-01-02"))
	}
}

// --- 辅助方法 ---

// rateLimitWait 控流等待
func (s *DoubanRankService) rateLimitWait(ctx context.Context) {
	intervalMs := s.configSvc.GetInt(ctx, configKeyRankSync, 4)
	if intervalMs <= 0 {
		intervalMs = 500
	}
	select {
	case <-time.After(time.Duration(intervalMs) * time.Millisecond):
	case <-ctx.Done():
	}
}

// today 获取今日日期（只保留日期部分）
func today() time.Time {
	now := time.Now()
	return time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
}

// countSubjectsInJSON 统计 JSON 数据中的条目数量
func countSubjectsInJSON(data string) int {
	var subj struct {
		Subjects []interface{} `json:"subjects"`
	}
	if err := json.Unmarshal([]byte(data), &subj); err != nil {
		var tags struct {
			Tags []interface{} `json:"tags"`
		}
		if err := json.Unmarshal([]byte(data), &tags); err != nil {
			return 0
		}
		return len(tags.Tags)
	}
	return len(subj.Subjects)
}
