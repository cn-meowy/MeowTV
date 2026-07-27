package response

// ResourceSiteResp 单个资源站点响应
type ResourceSiteResp struct {
	Domain     string `json:"domain"`
	Name       string `json:"name"`
	API        string `json:"api"`
	Detail     string `json:"detail"`
	Comment    string `json:"comment,omitempty"`
	CacheTime  int    `json:"cache_time,omitempty"`
	IsEnabled  bool   `json:"is_enabled"`
	IsAdult    bool   `json:"is_adult"`   // Value5=1 表示18禁
	Searchable bool   `json:"searchable"` // Value6=0 表示不允许搜索
}

// ResourceSubscribeResp 资源订阅配置响应
type ResourceSubscribeResp struct {
	SubscribeURL  string `json:"subscribe_url"`
	AutoSubscribe bool   `json:"auto_subscribe"`
	CronExpr      string `json:"cron_expr"`
}

// SubscribeResultResp 订阅拉取结果响应
type SubscribeResultResp struct {
	Total   int      `json:"total"`
	Added   int      `json:"added"`
	Updated int      `json:"updated"`
	Domains []string `json:"domains"`
}

// ResourceDetailResp 资源详情响应
type ResourceDetailResp struct {
	VodID          int64  `json:"vod_id"`
	VodName        string `json:"vod_name"`
	VodSub         string `json:"vod_sub,omitempty"`
	VodPic         string `json:"vod_pic,omitempty"`
	VodActor       string `json:"vod_actor,omitempty"`
	VodDirector    string `json:"vod_director,omitempty"`
	VodBlurb       string `json:"vod_blurb,omitempty"`
	VodContent     string `json:"vod_content,omitempty"`
	VodRemarks     string `json:"vod_remarks,omitempty"`
	VodArea        string `json:"vod_area,omitempty"`
	VodLang        string `json:"vod_lang,omitempty"`
	VodYear        string `json:"vod_year,omitempty"`
	VodScore       string `json:"vod_score,omitempty"`
	VodDoubanID    int64  `json:"vod_douban_id,omitempty"`
	VodDoubanScore string `json:"vod_douban_score,omitempty"`
	VodClass       string `json:"vod_class,omitempty"`
	VodPlayURL     string `json:"vod_play_url,omitempty"`
	TypeName       string `json:"type_name,omitempty"`
	TypeID1        int    `json:"type_id_1,omitempty"`
	ResourceDomain string `json:"resource_domain"`
	ResourceName   string `json:"resource_name"`
}

// ResourcePageResp 资源分页查询响应
type ResourcePageResp struct {
	Items      []SearchResultItem `json:"items"`
	Total      int                `json:"total"`
	Page       int                `json:"page"`
	PageSize   int                `json:"page_size"`
	TotalPages int                `json:"total_pages"`
}
