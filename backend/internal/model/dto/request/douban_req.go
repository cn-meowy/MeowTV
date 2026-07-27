package request

// DoubanSubjectsReq 分类列表请求
type DoubanSubjectsReq struct {
	Type      string `json:"type" validate:"required,oneof=movie tv"`
	Tag       string `json:"tag" validate:"omitempty,max=50"`
	Sort      string `json:"sort" validate:"omitempty,oneof=recommend=time rank"`
	PageLimit int    `json:"page_limit" validate:"omitempty,min=1,max=50"`
	PageStart int    `json:"page_start" validate:"omitempty,min=0"`
}

// DoubanTagsReq 分类列表请求
type DoubanTagsReq struct {
	Type string `json:"type" validate:"required,oneof=movie tv"`
}

// DoubanSubjectReq 影视详情请求（通用）
type DoubanSubjectReq struct {
	SubjectID string `json:"subject_id" validate:"required"`
}

// DoubanTop250Req Top250 榜单请求
type DoubanTop250Req struct {
	Start int `json:"start" validate:"omitempty,min=0"`
	Limit int `json:"limit" validate:"omitempty,min=1,max=50"`
}

// DoubanSearchSuggestReq 搜索建议请求
type DoubanSearchSuggestReq struct {
	Query string `json:"query" validate:"required,min=1,max=100"`
}

// DoubanReviewReq 影评/短评请求
type DoubanReviewReq struct {
	SubjectID string `json:"subject_id" validate:"required"`
	Start     int    `json:"start" validate:"omitempty,min=0"`
	Limit     int    `json:"limit" validate:"omitempty,min=1,max=50"`
}

// DoubanPhotosReq 剧照请求
type DoubanPhotosReq struct {
	SubjectID string `json:"subject_id" validate:"required"`
	Type      string `json:"type" validate:"omitempty,oneof=s still poster wallpaper"`
	Start     int    `json:"start" validate:"omitempty,min=0"`
	Limit     int    `json:"limit" validate:"omitempty,min=1,max=50"`
}

// DoubanCelebritiesReq 演职人员请求
type DoubanCelebritiesReq struct {
	SubjectID string `json:"subject_id" validate:"required"`
}

// ImageProxyReq 图片代理请求
type ImageProxyReq struct {
	URL string `query:"url" validate:"required,url"`
}
