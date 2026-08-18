package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/url"
	"strconv"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/entity"
)

// DoubanService 豆瓣代理业务层
type DoubanService struct {
	client       *DoubanClient
	rankService  *DoubanRankService
	localDataSvc *LocalDataService
}

// NewDoubanService 创建豆瓣代理 Service
func NewDoubanService(client *DoubanClient, rankService *DoubanRankService, localDataSvc *LocalDataService) *DoubanService {
	return &DoubanService{client: client, rankService: rankService, localDataSvc: localDataSvc}
}

// Subjects 获取分类列表（demo 模式优先本地，再从本地榜单读取，最后降级到实时请求）
// 对应豆瓣接口: /j/search_subjects
func (s *DoubanService) Subjects(ctx context.Context, rankType, tag string, pageLimit, pageStart int) (string, error) {
	// Demo 模式：从 local_video 表构造豆瓣 subjects 格式数据
	if s.localDataSvc != nil && s.localDataSvc.IsDemoMode() {
		if data, err := s.buildLocalSubjectsJSON(ctx, rankType, tag, pageLimit, pageStart); err == nil {
			return data, nil
		}
	}

	// 优先从本地榜单服务获取
	if s.rankService != nil {
		data, err := s.rankService.GetSubjects(ctx, rankType, tag, pageLimit, pageStart)
		if err == nil {
			return data, nil
		}
		// 本地获取失败，降级到实时请求
		slog.Warn("rank service get subjects failed, falling back to live API", "error", err)
	}

	query := buildSubjectsQuery(rankType, tag, pageLimit, pageStart)
	result, err := s.client.FetchJSON(ctx, "/j/search_subjects", query)
	if err != nil {
		return "", errs.WithMsg("获取豆瓣分类列表失败", errs.ErrServiceUnavailable)
	}
	return result, nil
}

// Tags 获取分类列表（demo 模式优先本地，再从本地榜单读取，最后降级到实时请求）
// 对应豆瓣接口: /j/search_tags
func (s *DoubanService) Tags(ctx context.Context, rankType string) (string, error) {
	// Demo 模式：从 local_video 表构造豆瓣 tags 格式数据
	if s.localDataSvc != nil && s.localDataSvc.IsDemoMode() {
		if data, err := s.buildLocalTagsJSON(ctx, rankType); err == nil {
			return data, nil
		}
	}

	// 优先从本地榜单服务获取
	if s.rankService != nil {
		data, err := s.rankService.GetTags(ctx, rankType)
		if err == nil {
			return data, nil
		}
		// 本地获取失败，降级到实时请求
		slog.Warn("rank service get tags failed, falling back to live API", "error", err)
	}

	query := "type=" + rankType
	result, err := s.client.FetchJSON(ctx, "/j/search_tags", query)
	if err != nil {
		return "", errs.WithMsg("获取豆瓣分类列表失败", errs.ErrServiceUnavailable)
	}
	return result, nil
}

// buildLocalSubjectsJSON 从 local_video 表构造豆瓣 subjects 格式 JSON
// 豆瓣返回格式: {"subjects":[{"id","title","cover","rate","url","cover_x":"..."}], "total": N}
// demo 模式下本地数据量小，tag 参数仅做兼容不做精确过滤，保证首页始终有数据
func (s *DoubanService) buildLocalSubjectsJSON(ctx context.Context, rankType, tag string, pageLimit, pageStart int) (string, error) {
	videos, err := s.localDataSvc.localVideoRepo.ListByType(rankType)
	if err != nil {
		slog.Warn("build local subjects failed", "error", err)
		return "", err
	}

	// 分页切片
	if pageLimit <= 0 {
		pageLimit = 20
	}
	if pageStart < 0 {
		pageStart = 0
	}
	total := len(videos)
	// 越界保护：pageStart >= total 时返回空列表而非越界切片
	if pageStart >= total {
		pageStart = total
	}
	end := pageStart + pageLimit
	if end > total {
		end = total
	}
	var sliced []entity.LocalVideo
	if pageStart < end {
		sliced = videos[pageStart:end]
	} else {
		sliced = []entity.LocalVideo{}
	}

	// 构造豆瓣 subjects 格式
	type localSubject struct {
		ID     string `json:"id"`
		Title  string `json:"title"`
		Cover  string `json:"cover"`
		Rate   string `json:"rate"`
		URL    string `json:"url"`
		CoverX string `json:"cover_x"`
		IsBe   string `json:"is_be"`
	}

	subjects := make([]localSubject, 0, len(sliced))
	for _, v := range sliced {
		subjects = append(subjects, localSubject{
			ID:     fmt.Sprintf("%d", v.VodID),
			Title:  v.VodName,
			Cover:  v.VodPic,
			Rate:   v.VodScore,
			URL:    fmt.Sprintf("https://movie.douban.com/subject/%d/", v.VodID),
			CoverX: "0",
			IsBe:   "",
		})
	}

	result := map[string]interface{}{
		"subjects": subjects,
		"total":    total,
	}

	data, err := json.Marshal(result)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// standardDoubanTags 豆瓣标准标签集合，与前端 DEFAULT_TAGS 保持一致
var standardDoubanTags = []string{"热门", "最新", "经典", "豆瓣高分", "冷门佳片"}

// buildLocalTagsJSON 返回豆瓣 tags 格式 JSON
// 豆瓣返回格式: {"tags":["热门","最新",...]}
// demo 模式下始终返回豆瓣标准标签集合，保证前端标签栏展示一致体验
// 实际文件夹分类会作为额外标签追加在标准标签之后
func (s *DoubanService) buildLocalTagsJSON(ctx context.Context, rankType string) (string, error) {
	tagSet := make(map[string]bool)
	// 1. 先加入豆瓣标准标签（保持顺序）
	for _, t := range standardDoubanTags {
		tagSet[t] = true
	}

	// 2. 追加实际 demo 数据的文件夹分类作为额外标签
	videos, err := s.localDataSvc.localVideoRepo.ListAll()
	if err != nil {
		slog.Warn("build local tags failed, using standard tags only", "error", err)
	} else {
		for _, v := range videos {
			if v.VodClass != "" {
				tagSet[v.VodClass] = true
			}
		}
	}

	// 标准标签按固定顺序优先，额外标签按出现顺序追加
	tags := make([]string, 0, len(tagSet))
	added := make(map[string]bool, len(tagSet))
	for _, t := range standardDoubanTags {
		tags = append(tags, t)
		added[t] = true
	}
	for t := range tagSet {
		if !added[t] {
			tags = append(tags, t)
			added[t] = true
		}
	}

	result := map[string]interface{}{
		"tags": tags,
	}

	data, err := json.Marshal(result)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// buildSubjectsQuery 构建分类列表查询参数
func buildSubjectsQuery(rankType, tag string, pageLimit, pageStart int) string {
	v := url.Values{}
	if rankType != "" {
		v.Set("type", rankType)
	}
	if tag != "" {
		v.Set("tag", tag)
	}
	if pageLimit > 0 {
		v.Set("page_limit", strconv.Itoa(pageLimit))
	}
	if pageStart > 0 {
		v.Set("page_start", strconv.Itoa(pageStart))
	}
	return v.Encode()
}

//// SubjectAbstract 获取影视简要信息
//// 对应豆瓣接口: /j/subject_abstract
//func (s *DoubanService) SubjectAbstract(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/subject_abstract", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣影视简介失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
//
//// SubjectDetail 获取影视完整详情
//// 对应豆瓣接口: /j/subject_detail
//func (s *DoubanService) SubjectDetail(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/subject_detail", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣影视详情失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
//
//// Top250 获取 Top250 榜单
//// 对应豆瓣接口: /j/top250
//func (s *DoubanService) Top250(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/top250", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣Top250失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
//
//// SearchSuggest 获取搜索建议
//// 对应豆瓣接口: /j/search_suggest
//func (s *DoubanService) SearchSuggest(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/search_suggest", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣搜索建议失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
//
//// Reviews 获取影评列表
//// 对应豆瓣接口: /j/subject_review
//func (s *DoubanService) Reviews(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/subject_review", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣影评失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
//
//// Comments 获取短评列表
//// 对应豆瓣接口: /j/subject_comments
//func (s *DoubanService) Comments(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/subject_comments", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣短评失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
//
//// Photos 获取剧照/海报
//// 对应豆瓣接口: /j/subject_photos
//func (s *DoubanService) Photos(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/subject_photos", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣剧照失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
//
//// Celebrities 获取演职人员
//// 对应豆瓣接口: /j/subject_celebrities
//func (s *DoubanService) Celebrities(ctx context.Context, query string) (string, error) {
//	result, err := s.client.FetchJSON(ctx, "/j/subject_celebrities", query)
//	if err != nil {
//		return "", errs.WithMsg("获取豆瓣演职人员失败", errs.ErrServiceUnavailable)
//	}
//	return result, nil
//}
