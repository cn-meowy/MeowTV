package service

import (
	"context"
	"log/slog"
	"net/url"
	"strconv"

	"cn.meow/meowtv/internal/errs"
)

// DoubanService 豆瓣代理业务层
type DoubanService struct {
	client      *DoubanClient
	rankService *DoubanRankService
}

// NewDoubanService 创建豆瓣代理 Service
func NewDoubanService(client *DoubanClient, rankService *DoubanRankService) *DoubanService {
	return &DoubanService{client: client, rankService: rankService}
}

// Subjects 获取分类列表（优先从本地榜单读取，降级到实时请求）
// 对应豆瓣接口: /j/search_subjects
func (s *DoubanService) Subjects(ctx context.Context, rankType, tag string, pageLimit, pageStart int) (string, error) {
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

// Tags 获取分类列表（优先从本地榜单读取，降级到实时请求）
// 对应豆瓣接口: /j/search_tags
func (s *DoubanService) Tags(ctx context.Context, rankType string) (string, error) {
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
