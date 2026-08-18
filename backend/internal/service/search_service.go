package service

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
	"cn.meow/meowtv/internal/util"
)

// --- MacCMS v10 原始数据解析结构 ---

// macCMSSearchResp MacCMS 搜索接口响应
type macCMSSearchResp struct {
	Code      int             `json:"code"`
	Msg       string          `json:"msg"`
	Page      util.FlexString `json:"page"`
	PageCount util.FlexString `json:"pagecount"`
	Limit     util.FlexString `json:"limit"`
	Total     util.FlexString `json:"total"`
	List      []macCMSVodItem `json:"list"`
}

// macCMSVodItem MacCMS 单条影视数据
// 注意：MacCMS 不同站点 API 实现不一致，整数字段可能返回字符串，
// 因此使用 util.FlexString 兼容数字和字符串两种 JSON 值
type macCMSVodItem struct {
	VodID          util.FlexString `json:"vod_id"`
	VodName        string          `json:"vod_name"`
	VodSub         string          `json:"vod_sub"`
	VodEn          string          `json:"vod_en"`
	VodStatus      util.FlexString `json:"vod_status"`
	VodLetter      string          `json:"vod_letter"`
	VodClass       string          `json:"vod_class"`
	VodPic         string          `json:"vod_pic"`
	VodActor       string          `json:"vod_actor"`
	VodDirector    string          `json:"vod_director"`
	VodBlurb       string          `json:"vod_blurb"`
	VodRemarks     string          `json:"vod_remarks"`
	VodArea        string          `json:"vod_area"`
	VodLang        string          `json:"vod_lang"`
	VodYear        string          `json:"vod_year"`
	VodScore       string          `json:"vod_score"`
	VodDoubanID    util.FlexString `json:"vod_douban_id"`
	VodDoubanScore string          `json:"vod_douban_score"`
	VodContent     string          `json:"vod_content"`
	VodPlayFrom    string          `json:"vod_play_from"`
	VodPlayURL     string          `json:"vod_play_url"`
	TypeName       string          `json:"type_name"`
	TypeID1        util.FlexString `json:"type_id_1"`
}

// --- 搜索结果通道消息 ---

// searchEvent SSE 推送事件
type searchEvent struct {
	EventType string      // result, done, complete, error
	Data      interface{} // SearchResultItem, SearchDoneData, SearchCompleteData, SearchErrorData
}

// siteInfo 资源站信息（用于并发查询）
type siteInfo struct {
	Domain     string
	Name       string
	APIURL     string
	IsNSFW     bool // 18禁标记
	Searchable bool
}

// SearchService 聚合搜索业务层
type SearchService struct {
	configService  *SysConfigService
	groupService   *UserGroupService
	cache          cache.Cache
	httpClient     *http.Client
	localVideoRepo *repository.LocalVideoRepository
	localDataSvc   *LocalDataService
}

// NewSearchService 创建聚合搜索 Service
func NewSearchService(configService *SysConfigService, groupService *UserGroupService, c cache.Cache, localVideoRepo *repository.LocalVideoRepository, localDataSvc *LocalDataService) *SearchService {
	return &SearchService{
		configService:  configService,
		groupService:   groupService,
		cache:          c,
		httpClient:     &http.Client{Timeout: 30 * 1e9}, // 30s
		localVideoRepo: localVideoRepo,
		localDataSvc:   localDataSvc,
	}
}

// Search 聚合搜索，通过 channel 流式返回结果
// 返回 channel 由调用方消费，channel 关闭表示搜索结束
func (s *SearchService) Search(ctx context.Context, userID int64, role int8, req *request.SearchReq) (<-chan searchEvent, error) {
	// 1. 验证用户对所选 resources 的权限
	allowedSites, err := s.getAllowedSites(ctx, userID, role, req.Resources)
	if err != nil {
		return nil, err
	}

	if len(allowedSites) == 0 {
		return nil, errs.WithMsg("没有可用的资源站点", errs.ErrBadRequest)
	}

	// 2. 存在 douban_id 时，过滤18禁站点
	hasDoubanID := req.DoubanID != ""
	sites := make([]*siteInfo, 0, len(allowedSites))
	for _, site := range allowedSites {
		if hasDoubanID && site.IsNSFW {
			slog.Debug("skipping nsfw site when douban_id present", "domain", site.Domain)
			continue
		}
		if !site.Searchable {
			slog.Debug("skipping NoSearch site ", "domain", site.Domain)
			continue
		}
		sites = append(sites, site)
	}

	if len(sites) == 0 {
		return nil, errs.WithMsg("过滤后没有可用的资源站点", errs.ErrBadRequest)
	}

	// 3. 创建事件 channel
	eventCh := make(chan searchEvent, 64)

	// 4. 启动并发搜索
	go s.concurrentSearch(ctx, sites, req.Q, req.DoubanID, eventCh)

	return eventCh, nil
}

// getAllowedSites 获取用户有权访问的、且在请求资源列表中的站点信息
func (s *SearchService) getAllowedSites(ctx context.Context, userID int64, role int8, requestedDomains []string) ([]*siteInfo, error) {
	// 构建请求 domain set
	reqSet := make(map[string]bool, len(requestedDomains))
	for _, d := range requestedDomains {
		reqSet[d] = true
	}

	// 获取用户可访问的站点列表（复用 ListSites 逻辑）
	var sites []*response.ResourceSiteResp
	var err error
	if entity.Role(role) == entity.RoleAdmin {
		sites, err = s.listAllSitesInternal(ctx)
	} else {
		sites, err = s.listUserSitesInternal(ctx, userID)
	}
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 交集：请求的资源 ∩ 用户有权访问的资源
	result := make([]*siteInfo, 0)
	for _, site := range sites {
		if !reqSet[site.Domain] {
			continue
		}
		// 获取 nsfw 标记（value5）
		isNSFW := s.isNSFWSite(ctx, site.Domain)
		result = append(result, &siteInfo{
			Domain:     site.Domain,
			Name:       site.Name,
			APIURL:     site.API,
			IsNSFW:     isNSFW,
			Searchable: site.Searchable,
		})
	}

	return result, nil
}

// listAllSitesInternal 管理员获取所有站点
func (s *SearchService) listAllSitesInternal(ctx context.Context) ([]*response.ResourceSiteResp, error) {
	// 复用 ResourceService 的 listAllSites 逻辑
	// 为避免循环依赖，这里直接查询 configService
	configs, err := s.configService.ListEnabledByGroup(ctx, "resource_site")
	if err != nil {
		return nil, err
	}

	list := make([]*response.ResourceSiteResp, 0, len(configs))
	for _, cfg := range configs {
		list = append(list, &response.ResourceSiteResp{
			Domain:     cfg.ConfigKey,
			Name:       cfg.Title,
			API:        cfg.Value1,
			Detail:     cfg.Value2,
			Comment:    cfg.Value3,
			CacheTime:  parseInt(cfg.Value4),
			IsEnabled:  cfg.IsEnabled,
			IsAdult:    cfg.Value5 == "1",
			Searchable: cfg.Value6 != "0",
		})
	}
	return list, nil
}

// listUserSitesInternal 普通用户按用户组过滤站点
func (s *SearchService) listUserSitesInternal(ctx context.Context, userID int64) ([]*response.ResourceSiteResp, error) {
	if s.groupService == nil {
		return []*response.ResourceSiteResp{}, nil
	}

	groupID, err := s.groupService.GetUserGroupID(ctx, userID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}
	if groupID == nil {
		return []*response.ResourceSiteResp{}, nil
	}

	configKeys, err := s.groupService.GetGroupResources(ctx, *groupID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}
	if len(configKeys) == 0 {
		return []*response.ResourceSiteResp{}, nil
	}

	configs, err := s.configService.ListEnabledByGroup(ctx, "resource_site")
	if err != nil {
		return nil, err
	}

	keySet := make(map[string]bool, len(configKeys))
	for _, k := range configKeys {
		keySet[k] = true
	}

	list := make([]*response.ResourceSiteResp, 0)
	for _, cfg := range configs {
		if !keySet[cfg.ConfigKey] {
			continue
		}
		list = append(list, &response.ResourceSiteResp{
			Domain:     cfg.ConfigKey,
			Name:       cfg.Title,
			API:        cfg.Value1,
			Detail:     cfg.Value2,
			Comment:    cfg.Value3,
			CacheTime:  parseInt(cfg.Value4),
			IsEnabled:  cfg.IsEnabled,
			IsAdult:    cfg.Value5 == "1",
			Searchable: cfg.Value6 != "0",
		})
	}
	return list, nil
}

// isNSFWSite 判断资源站是否为18禁（value5 = "1"）
func (s *SearchService) isNSFWSite(ctx context.Context, domain string) bool {
	cfg := s.configService.GetValue(ctx, domain)
	if cfg == nil {
		return false
	}
	return cfg.Value5 == "1"
}

// concurrentSearch 并发搜索各资源站
func (s *SearchService) concurrentSearch(ctx context.Context, sites []*siteInfo, keyword, doubanID string, eventCh chan<- searchEvent) {
	defer close(eventCh)

	var wg sync.WaitGroup
	var mu sync.Mutex // 保护 eventCh 写入的顺序性
	total := 0

	for _, site := range sites {
		wg.Add(1)
		go func(si *siteInfo) {
			defer wg.Done() // 确保 wg.Done 一定被调用
			defer func() {
				if r := recover(); r != nil {
					slog.Error("search goroutine panic recovered",
						"domain", si.Domain,
						"panic", r)
					// 发送 error 事件
					mu.Lock()
					eventCh <- searchEvent{
						EventType: "error",
						Data: response.SearchErrorData{
							ResourceDomain: si.Domain,
							Message:        "搜索过程发生异常",
						},
					}
					mu.Unlock()
					// 推送 done 事件（计数为0）
					mu.Lock()
					eventCh <- searchEvent{
						EventType: "done",
						Data: response.SearchDoneData{
							ResourceDomain: si.Domain,
							Count:          0,
						},
					}
					mu.Unlock()
				}
			}()

			// 正常流程：调用搜索并发送 done 事件
			count := s.searchSite(ctx, si, keyword, doubanID, eventCh, &mu)
			mu.Lock()
			total += count
			mu.Unlock()

			// 推送 done 事件
			slog.Info("search site done", "domain", si.Domain, "count", count)
			mu.Lock()
			eventCh <- searchEvent{
				EventType: "done",
				Data: response.SearchDoneData{
					ResourceDomain: si.Domain,
					Count:          count,
				},
			}
			mu.Unlock()
		}(site)
	}

	// 等待所有 goroutine 完成
	wg.Wait()

	// 推送 complete 事件
	eventCh <- searchEvent{
		EventType: "complete",
		Data: response.SearchCompleteData{
			Total: total,
		},
	}
}

// searchSite 搜索单个资源站，返回结果数量
func (s *SearchService) searchSite(ctx context.Context, site *siteInfo, keyword, doubanID string, eventCh chan<- searchEvent, mu *sync.Mutex) int {
	slog.Info("search site start", "domain", site.Domain, "keyword", keyword)

	// Demo 模式：本地演示站点走数据库查询
	if s.isLocalDemoSite(site.Domain) {
		return s.searchLocalSite(ctx, site, keyword, eventCh, mu)
	}

	// 1. 先查缓存
	queryHash := hashQuery(keyword)
	ck := cache.KeyResourceSearch(site.Domain, queryHash)
	if cached, err := s.cache.Get(ctx, ck.Key); err == nil && cached != "" {
		var items []response.SearchResultItem
		if json.Unmarshal([]byte(cached), &items) == nil {
			for _, item := range items {
				if doubanID != "" && doubanID != item.DoubanID {
					continue
				}
				mu.Lock()
				eventCh <- searchEvent{EventType: "result", Data: item}
				mu.Unlock()
			}
			return len(items)
		}
	}

	// 2. 构建 HTTP 请求
	searchURL := fmt.Sprintf("%s?ac=detail&wd=%s", strings.TrimRight(site.APIURL, "/"), url.QueryEscape(keyword))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, searchURL, nil)
	if err != nil {
		slog.Error("build search request failed", "domain", site.Domain, "error", err)
		mu.Lock()
		eventCh <- searchEvent{
			EventType: "error",
			Data: response.SearchErrorData{
				ResourceDomain: site.Domain,
				Message:        "构建请求失败",
			},
		}
		mu.Unlock()
		return 0
	}

	// 设置请求头，模拟浏览器访问
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Referer", site.APIURL)

	slog.Debug("searching site", "domain", site.Domain, "url", searchURL)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		slog.Error("search request failed", "domain", site.Domain, "url", searchURL, "error", err)
		//mu.Lock()
		//eventCh <- searchEvent{
		//	EventType: "error",
		//	Data: response.SearchErrorData{
		//		ResourceDomain: site.Domain,
		//		Message:        "请求资源站失败",
		//	},
		//}
		//mu.Unlock()
		return 0
	}
	defer func(Body io.ReadCloser) {
		_ = Body.Close()
	}(resp.Body)

	if resp.StatusCode != http.StatusOK {
		slog.Error("search request bad status", "domain", site.Domain, "status", resp.StatusCode)
		//mu.Lock()
		//eventCh <- searchEvent{
		//	EventType: "error",
		//	Data: response.SearchErrorData{
		//		ResourceDomain: site.Domain,
		//		Message:        fmt.Sprintf("资源站返回异常状态码: %d", resp.StatusCode),
		//	},
		//}
		//mu.Unlock()
		return 0
	}

	// 3. 读取响应
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Error("read search response failed", "domain", site.Domain, "error", err)
		//mu.Lock()
		//eventCh <- searchEvent{
		//	EventType: "error",
		//	Data: response.SearchErrorData{
		//		ResourceDomain: site.Domain,
		//		Message:        "读取响应失败",
		//	},
		//}
		//mu.Unlock()
		return 0
	}

	// 4. 解析 MacCMS JSON
	var macResp macCMSSearchResp
	if err := json.Unmarshal(body, &macResp); err != nil {
		slog.Error("parse macCMS response failed", "domain", site.Domain, "error", err, "body_len", len(body))
		//mu.Lock()
		//eventCh <- searchEvent{
		//	EventType: "error",
		//	Data: response.SearchErrorData{
		//		ResourceDomain: site.Domain,
		//		Message:        "解析响应数据失败",
		//	},
		//}
		//mu.Unlock()
		return 0
	}

	if macResp.Code != 1 {
		slog.Error("macCMS response error", "domain", site.Domain, "code", macResp.Code, "msg", macResp.Msg)
		//mu.Lock()
		//eventCh <- searchEvent{
		//	EventType: "error",
		//	Data: response.SearchErrorData{
		//		ResourceDomain: site.Domain,
		//		Message:        macResp.Msg,
		//	},
		//}
		//mu.Unlock()
		return 0
	}

	// 5. 映射为统一结构并推送
	items := make([]response.SearchResultItem, 0, len(macResp.List))
	for _, vod := range macResp.List {
		item := s.mapVodToResult(site, &vod)
		items = append(items, item)

		// 推送 result 事件
		if doubanID != "" && doubanID != vod.VodDoubanID.String() {
			continue
		}
		mu.Lock()
		eventCh <- searchEvent{EventType: "result", Data: item}
		mu.Unlock()
	}

	// 6. 写入缓存
	if data, err := json.Marshal(items); err == nil {
		_ = s.cache.Set(ctx, ck.Key, string(data), ck.TTL)
	}

	slog.Info("search site end", "domain", site.Domain, "count", len(items))
	return len(items)
}

// mapVodToResult 将 MacCMS vod 映射为统一的搜索结果
func (s *SearchService) mapVodToResult(site *siteInfo, vod *macCMSVodItem) response.SearchResultItem {
	doubanID := ""
	if vod.VodDoubanID.Int64() > 0 {
		doubanID = vod.VodDoubanID.String()
	}

	return response.SearchResultItem{
		VodID:          vod.VodID.Int64(),
		ResourceDomain: site.Domain,
		ResourceName:   site.Name,
		Title:          vod.VodName,
		Subtitle:       vod.VodSub,
		DoubanID:       doubanID,
		DoubanScore:    vod.VodDoubanScore,
		Year:           vod.VodYear,
		Type:           vod.TypeName,
		TypeID1:        vod.TypeID1.Int(),
		Genre:          vod.VodClass,
		Cover:          vod.VodPic,
		Actors:         vod.VodActor,
		Director:       vod.VodDirector,
		Description:    vod.VodBlurb,
		Remarks:        vod.VodRemarks,
		Area:           vod.VodArea,
		Lang:           vod.VodLang,
		Score:          vod.VodScore,
		PlayFrom:       vod.VodPlayFrom,
		PlayURL:        vod.VodPlayURL,
	}
}

// hashQuery 生成搜索关键词的哈希值（用于缓存 key）
func hashQuery(keyword string) string {
	h := sha256.New()
	h.Write([]byte(keyword))
	return fmt.Sprintf("%x", h.Sum(nil))[:16]
}

// Detail 查询单个资源站的影视详情
func (s *SearchService) Detail(ctx context.Context, userID int64, role int8, req *request.ResourceDetailReq) (*response.ResourceDetailResp, error) {
	// 1. 权限验证：检查用户是否有权访问该 site
	siteInfo, err := s.getAllowedSite(ctx, userID, role, req.Site)
	if err != nil {
		return nil, err
	}

	// Demo 模式：本地演示站点走数据库查询
	if s.isLocalDemoSite(siteInfo.Domain) {
		return s.getLocalDetail(ctx, siteInfo, req.VodID)
	}

	// 2. 先查缓存
	ck := cache.KeyResourceDetail(siteInfo.Domain, req.VodID)
	if cached, err := s.cache.Get(ctx, ck.Key); err == nil && cached != "" {
		var detail response.ResourceDetailResp
		if json.Unmarshal([]byte(cached), &detail) == nil {
			return &detail, nil
		}
	}

	// 3. 构建 HTTP 请求
	detailURL := fmt.Sprintf("%s?ac=detail&ids=%d", strings.TrimRight(siteInfo.DetailURL, "/"), req.VodID)
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, detailURL, nil)
	if err != nil {
		slog.Error("build detail request failed", "domain", siteInfo.Domain, "error", err)
		return nil, errs.WithMsg("构建详情请求失败", errs.ErrInternal)
	}

	httpReq.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	httpReq.Header.Set("Accept", "application/json, text/plain, */*")
	httpReq.Header.Set("Referer", siteInfo.DetailURL)

	slog.Debug("fetching detail", "domain", siteInfo.Domain, "url", detailURL)

	resp, err := s.httpClient.Do(httpReq)
	if err != nil {
		slog.Error("detail request failed", "domain", siteInfo.Domain, "error", err)
		return nil, errs.WithMsg("请求资源站详情失败", errs.ErrInternal)
	}
	defer func(Body io.ReadCloser) { _ = Body.Close() }(resp.Body)

	if resp.StatusCode != http.StatusOK {
		slog.Error("detail request bad status", "domain", siteInfo.Domain, "status", resp.StatusCode)
		return nil, errs.WithMsg(fmt.Sprintf("资源站返回异常状态码: %d", resp.StatusCode), errs.ErrInternal)
	}

	// 4. 读取响应
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Error("read detail response failed", "domain", siteInfo.Domain, "error", err)
		return nil, errs.WithMsg("读取详情响应失败", errs.ErrInternal)
	}

	// 5. 解析 MacCMS JSON
	var macResp macCMSSearchResp
	if err := json.Unmarshal(body, &macResp); err != nil {
		slog.Error("parse macCMS detail response failed", "domain", siteInfo.Domain, "error", err, "body_len", len(body))
		return nil, errs.WithMsg("解析详情数据失败", errs.ErrInternal)
	}

	if macResp.Code != 1 || len(macResp.List) == 0 {
		return nil, errs.WithMsg("未找到详情数据", errs.ErrNotFound)
	}

	// 6. 映射为 ResourceDetailResp
	vod := &macResp.List[0]
	detail := s.mapVodToDetail(siteInfo, vod)

	// 7. 写入缓存
	if data, err := json.Marshal(detail); err == nil {
		_ = s.cache.Set(ctx, ck.Key, string(data), ck.TTL)
	}

	return detail, nil
}

// detailSiteInfo 详情查询所需的站点信息
type detailSiteInfo struct {
	Domain    string
	Name      string
	DetailURL string
}

// getAllowedSite 验证单个站点权限并返回站点信息
func (s *SearchService) getAllowedSite(ctx context.Context, userID int64, role int8, domain string) (*detailSiteInfo, error) {
	// 获取用户可访问的站点列表
	var sites []*response.ResourceSiteResp
	var err error
	if entity.Role(role) == entity.RoleAdmin {
		sites, err = s.listAllSitesInternal(ctx)
	} else {
		sites, err = s.listUserSitesInternal(ctx, userID)
	}
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 查找匹配的站点
	for _, site := range sites {
		if site.Domain == domain {
			if site.Detail == "" {
				return nil, errs.WithMsg("该资源站未配置详情接口", errs.ErrNotFound)
			}
			return &detailSiteInfo{
				Domain:    site.Domain,
				Name:      site.Name,
				DetailURL: site.API,
			}, nil
		}
	}

	return nil, errs.WithMsg("无权限访问该资源站", errs.ErrForbidden)
}

// mapVodToDetail 将 MacCMS vod 映射为资源详情响应
func (s *SearchService) mapVodToDetail(site *detailSiteInfo, vod *macCMSVodItem) *response.ResourceDetailResp {
	return &response.ResourceDetailResp{
		VodID:          vod.VodID.Int64(),
		VodName:        vod.VodName,
		VodSub:         vod.VodSub,
		VodPic:         vod.VodPic,
		VodActor:       vod.VodActor,
		VodDirector:    vod.VodDirector,
		VodBlurb:       vod.VodBlurb,
		VodContent:     vod.VodContent,
		VodRemarks:     vod.VodRemarks,
		VodArea:        vod.VodArea,
		VodLang:        vod.VodLang,
		VodYear:        vod.VodYear,
		VodScore:       vod.VodScore,
		VodDoubanID:    vod.VodDoubanID.Int64(),
		VodDoubanScore: vod.VodDoubanScore,
		VodClass:       vod.VodClass,
		VodPlayURL:     vod.VodPlayURL,
		TypeName:       vod.TypeName,
		TypeID1:        vod.TypeID1.Int(),
		ResourceDomain: site.Domain,
		ResourceName:   site.Name,
	}
}

// Paginate 资源分页查询（单个资源站，普通 JSON 响应）
func (s *SearchService) Paginate(ctx context.Context, userID int64, role int8, req *request.ResourcePageReq) (*response.ResourcePageResp, error) {
	// 1. 权限验证：验证用户是否有权访问该资源站
	allowedSite, err := s.getAllowedSite(ctx, userID, role, req.Resource)
	if err != nil {
		return nil, err
	}

	// Demo 模式：本地演示站点走数据库查询
	if s.isLocalDemoSite(allowedSite.Domain) {
		return s.getLocalPaginate(ctx, allowedSite, req.Page, req.PageSize, req.Keyword)
	}

	// 2. 构建 MacCMS API 请求 URL
	paginateURL := fmt.Sprintf("%s?ac=detail&pg=%d&pagesize=%d", strings.TrimRight(allowedSite.DetailURL, "/"), req.Page, req.PageSize)
	if req.Keyword != "" {
		paginateURL += fmt.Sprintf("&wd=%s", url.QueryEscape(req.Keyword))
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, paginateURL, nil)
	if err != nil {
		slog.Error("build paginate request failed", "domain", allowedSite.Domain, "error", err)
		return nil, errs.WithMsg("构建分页请求失败", errs.ErrInternal)
	}

	httpReq.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	httpReq.Header.Set("Accept", "application/json, text/plain, */*")
	httpReq.Header.Set("Referer", allowedSite.DetailURL)

	slog.Debug("paginating site", "domain", allowedSite.Domain, "url", paginateURL, "page", req.Page, "pagesize", req.PageSize)

	// 3. 发送 HTTP 请求
	resp, err := s.httpClient.Do(httpReq)
	if err != nil {
		slog.Error("paginate request failed", "domain", allowedSite.Domain, "url", paginateURL, "error", err)
		return nil, errs.WithMsg("请求资源站失败", errs.ErrInternal)
	}
	defer func(Body io.ReadCloser) { _ = Body.Close() }(resp.Body)

	if resp.StatusCode != http.StatusOK {
		slog.Error("paginate request bad status", "domain", allowedSite.Domain, "status", resp.StatusCode)
		return nil, errs.WithMsg(fmt.Sprintf("资源站返回异常状态码: %d", resp.StatusCode), errs.ErrInternal)
	}

	// 4. 读取响应
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		slog.Error("read paginate response failed", "domain", allowedSite.Domain, "error", err)
		return nil, errs.WithMsg("读取分页响应失败", errs.ErrInternal)
	}

	// 5. 解析 MacCMS JSON
	var macResp macCMSSearchResp
	if err := json.Unmarshal(body, &macResp); err != nil {
		slog.Error("parse macCMS paginate response failed", "domain", allowedSite.Domain, "error", err, "body_len", len(body))
		return nil, errs.WithMsg("解析分页数据失败", errs.ErrInternal)
	}

	if macResp.Code != 1 {
		slog.Error("macCMS paginate response error", "domain", allowedSite.Domain, "code", macResp.Code, "msg", macResp.Msg)
		return nil, errs.WithMsg(macResp.Msg, errs.ErrInternal)
	}

	// 6. 映射为统一结构
	si := &siteInfo{
		Domain: allowedSite.Domain,
		Name:   allowedSite.Name,
	}
	items := make([]response.SearchResultItem, 0, len(macResp.List))
	for _, vod := range macResp.List {
		items = append(items, s.mapVodToResult(si, &vod))
	}

	// 7. 计算总页数
	totalPages := 0
	if macResp.PageCount.Int() > 0 {
		totalPages = macResp.PageCount.Int()
	} else if req.PageSize > 0 {
		totalPages = (macResp.Total.Int() + req.PageSize - 1) / req.PageSize
	}

	return &response.ResourcePageResp{
		Items:      items,
		Total:      macResp.Total.Int(),
		Page:       req.Page,
		PageSize:   req.PageSize,
		TotalPages: totalPages,
	}, nil
}

// --- Demo 模式：本地数据查询 ---

// isLocalDemoSite 判断站点是否为本地演示虚拟站点
func (s *SearchService) isLocalDemoSite(domain string) bool {
	return s.localDataSvc != nil && s.localDataSvc.IsDemoMode() && domain == DemoDomain
}

// searchLocalSite 从本地 local_video 表搜索并推送结果
func (s *SearchService) searchLocalSite(ctx context.Context, site *siteInfo, keyword string, eventCh chan<- searchEvent, mu *sync.Mutex) int {
	videos, err := s.localVideoRepo.SearchByKeyword(keyword)
	if err != nil {
		slog.Error("search local videos failed", "keyword", keyword, "error", err)
		return 0
	}

	count := 0
	for _, video := range videos {
		item := mapLocalVideoToResult(site, &video)
		mu.Lock()
		eventCh <- searchEvent{EventType: "result", Data: item}
		mu.Unlock()
		count++
	}
	return count
}

// getLocalDetail 从本地表获取详情
func (s *SearchService) getLocalDetail(ctx context.Context, site *detailSiteInfo, vodID int64) (*response.ResourceDetailResp, error) {
	video, err := s.localVideoRepo.GetByID(vodID)
	if err != nil {
		return nil, errs.WithMsg("未找到本地详情数据", errs.ErrNotFound)
	}
	return mapLocalVideoToDetail(site, video), nil
}

// getLocalPaginate 从本地表分页查询
func (s *SearchService) getLocalPaginate(ctx context.Context, site *detailSiteInfo, page, pageSize int, keyword string) (*response.ResourcePageResp, error) {
	videos, total, err := s.localVideoRepo.Paginate(page, pageSize, keyword)
	if err != nil {
		return nil, errs.WithMsg("本地分页查询失败", errs.ErrInternal)
	}

	si := &siteInfo{
		Domain: site.Domain,
		Name:   site.Name,
	}
	items := make([]response.SearchResultItem, 0, len(videos))
	for _, video := range videos {
		items = append(items, mapLocalVideoToResult(si, &video))
	}

	totalPages := 0
	if pageSize > 0 {
		totalPages = (int(total) + pageSize - 1) / pageSize
	}

	return &response.ResourcePageResp{
		Items:      items,
		Total:      int(total),
		Page:       page,
		PageSize:   pageSize,
		TotalPages: totalPages,
	}, nil
}

// mapLocalVideoToResult 将 LocalVideo 映射为搜索结果
func mapLocalVideoToResult(site *siteInfo, video *entity.LocalVideo) response.SearchResultItem {
	return response.SearchResultItem{
		VodID:          video.VodID,
		ResourceDomain: site.Domain,
		ResourceName:   site.Name,
		Title:          video.VodName,
		Subtitle:       video.VodSub,
		Year:           video.VodYear,
		Type:           video.TypeName,
		Genre:          video.VodClass,
		Cover:          video.VodPic,
		Actors:         video.VodActor,
		Director:       video.VodDirector,
		Description:    video.VodBlurb,
		Remarks:        video.VodRemarks,
		Area:           video.VodArea,
		Lang:           video.VodLang,
		Score:          video.VodScore,
		PlayFrom:       video.VodPlayFrom,
		PlayURL:        video.VodPlayURL,
	}
}

// mapLocalVideoToDetail 将 LocalVideo 映射为详情响应
func mapLocalVideoToDetail(site *detailSiteInfo, video *entity.LocalVideo) *response.ResourceDetailResp {
	return &response.ResourceDetailResp{
		VodID:          video.VodID,
		VodName:        video.VodName,
		VodSub:         video.VodSub,
		VodPic:         video.VodPic,
		VodActor:       video.VodActor,
		VodDirector:    video.VodDirector,
		VodBlurb:       video.VodBlurb,
		VodContent:     video.VodContent,
		VodRemarks:     video.VodRemarks,
		VodArea:        video.VodArea,
		VodLang:        video.VodLang,
		VodYear:        video.VodYear,
		VodScore:       video.VodScore,
		VodClass:       video.VodClass,
		VodPlayURL:     video.VodPlayURL,
		TypeName:       video.TypeName,
		ResourceDomain: site.Domain,
		ResourceName:   site.Name,
	}
}
