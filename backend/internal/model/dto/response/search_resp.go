package response

// SearchResultItem 单条搜索结果
type SearchResultItem struct {
	VodID          int64  `json:"vod_id,omitempty"`
	ResourceDomain string `json:"resource_domain"`
	ResourceName   string `json:"resource_name"`
	Title          string `json:"title"`
	Subtitle       string `json:"subtitle,omitempty"`
	DoubanID       string `json:"douban_id,omitempty"`
	DoubanScore    string `json:"douban_score,omitempty"`
	Year           string `json:"year,omitempty"`
	Type           string `json:"type,omitempty"`
	TypeID1        int    `json:"type_id_1,omitempty"`
	Genre          string `json:"genre,omitempty"`
	Cover          string `json:"cover,omitempty"`
	Actors         string `json:"actors,omitempty"`
	Director       string `json:"director,omitempty"`
	Description    string `json:"description,omitempty"`
	Remarks        string `json:"remarks,omitempty"`
	Area           string `json:"area,omitempty"`
	Lang           string `json:"lang,omitempty"`
	Score          string `json:"score,omitempty"`
	PlayFrom       string `json:"play_from,omitempty"`
	PlayURL        string `json:"play_url,omitempty"`
}

// SearchDoneData 单个资源搜索完成
type SearchDoneData struct {
	ResourceDomain string `json:"resource_domain"`
	Count          int    `json:"count"`
}

// SearchCompleteData 全部搜索完成
type SearchCompleteData struct {
	Total int `json:"total"`
}

// SearchErrorData 搜索错误
type SearchErrorData struct {
	ResourceDomain string `json:"resource_domain"`
	Message        string `json:"message"`
}
