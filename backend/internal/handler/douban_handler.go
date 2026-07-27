package handler

import (
	"encoding/json"
	"log/slog"
	"net/url"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/service"
)

// DoubanHandler 豆瓣代理接口
type DoubanHandler struct {
	doubanService *service.DoubanService
	imageService  *service.DoubanImageService
}

// NewDoubanHandler 创建豆瓣代理 Handler
func NewDoubanHandler(doubanService *service.DoubanService, imageService *service.DoubanImageService) *DoubanHandler {
	return &DoubanHandler{
		doubanService: doubanService,
		imageService:  imageService,
	}
}

// Subjects 分类列表（优先从本地榜单读取）
func (h *DoubanHandler) Subjects(c echo.Context) error {
	req := new(request.DoubanSubjectsReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		slog.Debug("validation error", "error", err.Error())
		return errs.WithMsg("请求参数校验失败", errs.ErrBadRequest)
	}

	tag := req.Tag
	if tag == "" {
		tag = "热门"
	}

	return h.proxyJSON(c, func() (string, error) {
		return h.doubanService.Subjects(c.Request().Context(), req.Type, tag, req.PageLimit, req.PageStart)
	})
}

// Tags 分类列表（优先从本地榜单读取）
func (h *DoubanHandler) Tags(c echo.Context) error {
	req := new(request.DoubanTagsReq)
	if err := c.Bind(req); err != nil {
		return errs.WithMsg("请求参数错误", errs.ErrBadRequest)
	}
	if err := c.Validate(req); err != nil {
		slog.Debug("validation error", "error", err.Error())
		return errs.WithMsg("请求参数校验失败", errs.ErrBadRequest)
	}

	return h.proxyJSON(c, func() (string, error) {
		return h.doubanService.Tags(c.Request().Context(), req.Type)
	})
}

//
//// SubjectAbstract 影视简要信息
//func (h *DoubanHandler) SubjectAbstract(c echo.Context) error {
//	q := buildQuery(c, "subject_id")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.SubjectAbstract(c.Request().Context(), q)
//	})
//}
//
//// SubjectDetail 影视完整详情
//func (h *DoubanHandler) SubjectDetail(c echo.Context) error {
//	q := buildQuery(c, "subject_id")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.SubjectDetail(c.Request().Context(), q)
//	})
//}
//
//// Top250 Top250 榜单
//func (h *DoubanHandler) Top250(c echo.Context) error {
//	q := buildQuery(c, "start", "limit")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.Top250(c.Request().Context(), q)
//	})
//}
//
//// SearchSuggest 搜索建议
//func (h *DoubanHandler) SearchSuggest(c echo.Context) error {
//	q := buildQuery(c, "q")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.SearchSuggest(c.Request().Context(), q)
//	})
//}
//
//// Reviews 影评列表
//func (h *DoubanHandler) Reviews(c echo.Context) error {
//	q := buildQuery(c, "subject_id", "start", "limit")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.Reviews(c.Request().Context(), q)
//	})
//}
//
//// Comments 短评列表
//func (h *DoubanHandler) Comments(c echo.Context) error {
//	q := buildQuery(c, "subject_id", "start", "limit")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.Comments(c.Request().Context(), q)
//	})
//}
//
//// Photos 剧照/海报
//func (h *DoubanHandler) Photos(c echo.Context) error {
//	q := buildQuery(c, "subject_id", "type", "start", "limit")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.Photos(c.Request().Context(), q)
//	})
//}
//
//// Celebrities 演职人员
//func (h *DoubanHandler) Celebrities(c echo.Context) error {
//	q := buildQuery(c, "subject_id")
//	return h.proxyJSON(c, func() (string, error) {
//		return h.doubanService.Celebrities(c.Request().Context(), q)
//	})
//}

// ImageProxy 图片代理（token 验证已由 TempTokenAuth 中间件完成）
func (h *DoubanHandler) ImageProxy(c echo.Context) error {
	imageURL := c.QueryParam("url")

	if imageURL == "" {
		return errs.WithMsg("缺少 url 参数", errs.ErrBadRequest)
	}

	return h.imageService.ProxyImage(c, imageURL)
}

// proxyJSON 通用 JSON 代理响应处理，将豆瓣返回数据用统一 Response 结构包裹后返回
func (h *DoubanHandler) proxyJSON(c echo.Context, fetch func() (string, error)) error {
	result, err := fetch()
	if err != nil {
		return err
	}
	var data interface{}
	if err := json.Unmarshal([]byte(result), &data); err != nil {
		return errs.WithMsg("解析豆瓣响应数据失败", errs.ErrInternal)
	}
	return response.OK(c, data)
}

// buildQuery 从请求参数构建查询字符串
func buildQuery(c echo.Context, params ...string) string {
	v := url.Values{}
	for _, p := range params {
		val := c.QueryParam(p)
		if val != "" {
			v.Set(p, val)
		}
	}
	// 也支持 POST body 中的参数
	if c.Request().Method == "POST" {
		for _, p := range params {
			if v.Get(p) != "" {
				continue
			}
			val := c.FormValue(p)
			if val != "" {
				v.Set(p, val)
			}
		}
	}
	return v.Encode()
}
