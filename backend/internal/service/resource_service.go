package service

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/robfig/cron/v3"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/util"
)

// subscribeData 订阅地址返回的数据结构
type subscribeData struct {
	CacheTime int                 `json:"cache_time"`
	ApiSite   map[string]siteItem `json:"api_site"`
}

// siteItem 单个站点数据
type siteItem struct {
	Name    string `json:"name"`
	API     string `json:"api"`
	Detail  string `json:"detail"`
	Comment string `json:"_comment,omitempty"`
}

const (
	// configKeySubscribe 资源订阅配置 key
	configKeySubscribe   = "resource_subscribe"
	configKeyProxy       = "resource_proxy"
	configGroupSubscribe = "resource_subscribe"
	configGroupSite      = "resource_site"
)

// ResourceService 资源订阅业务层
type ResourceService struct {
	configService *SysConfigService
	groupService  *UserGroupService
	cache         cache.Cache
	cron          *cron.Cron
	cronEntryID   cron.EntryID
	mu            sync.RWMutex
	httpClient    *http.Client
}

// NewResourceService 创建资源订阅 Service
func NewResourceService(configService *SysConfigService, groupService *UserGroupService, cache cache.Cache) *ResourceService {
	return &ResourceService{
		configService: configService,
		groupService:  groupService,
		cache:         cache,
		httpClient:    &http.Client{Timeout: 30 * time.Second}, // 30s, configurable via http_client.timeout
	}
}

// GetSubscribeConfig 获取订阅配置
func (s *ResourceService) GetSubscribeConfig(ctx context.Context) (*response.ResourceSubscribeResp, error) {
	cfg := s.configService.GetValue(ctx, configKeySubscribe)
	if cfg == nil {
		return nil, errs.WithMsg("订阅配置不存在", errs.ErrNotFound)
	}
	return &response.ResourceSubscribeResp{
		SubscribeURL:  cfg.Value1,
		AutoSubscribe: parseBool(cfg.Value2),
		CronExpr:      cfg.Value3,
	}, nil
}

// UpdateSubscribeConfig 更新订阅配置
func (s *ResourceService) UpdateSubscribeConfig(ctx context.Context, req *request.ResourceSubscribeUpdateReq) error {
	cfg, err := s.configService.GetByKey(ctx, configKeySubscribe)
	if err != nil {
		return errs.WithMsg("订阅配置不存在", errs.ErrNotFound)
	}

	if req.SubscribeURL != nil {
		cfg.Value1 = *req.SubscribeURL
	}
	if req.AutoSubscribe != nil {
		cfg.Value2 = strconv.FormatBool(*req.AutoSubscribe)
	}
	if req.CronExpr != nil {
		// 校验 cron 表达式
		parser := cron.NewParser(cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow)
		if _, err := parser.Parse(*req.CronExpr); err != nil {
			return errs.WithMsg("Cron 表达式格式错误: "+err.Error(), errs.ErrBadRequest)
		}
		cfg.Value3 = *req.CronExpr
	}

	updateReq := &request.ConfigUpdateReq{
		ConfigKey: cfg.ConfigKey,
		Value1:    &cfg.Value1,
		Value2:    &cfg.Value2,
		Value3:    &cfg.Value3,
	}

	if err := s.configService.Update(ctx, updateReq); err != nil {
		return err
	}

	// cron 重启已由 SysConfigService 的 onUpdate 回调自动处理，无需手动调用

	return nil
}

// FetchAndSaveSites 拉取订阅地址并保存站点
func (s *ResourceService) FetchAndSaveSites(ctx context.Context) (*response.SubscribeResultResp, error) {
	cfg := s.configService.GetValue(ctx, configKeySubscribe)
	if cfg == nil || cfg.Value1 == "" {
		return nil, errs.WithMsg("请先配置订阅地址", errs.ErrBadRequest)
	}

	// 1. HTTP GET 订阅地址
	body, err := s.fetchSubscribe(ctx, cfg.Value1)
	if err != nil {
		return nil, err
	}

	// 2. Base58 解码
	decoded, err := util.Decode(body)
	if err != nil {
		slog.Error("base58 decode failed", "error", err, "raw_length", len(body))
		return nil, errs.WithMsg("订阅数据格式错误（Base58 解码失败）", errs.ErrInternal)
	}

	// 3. JSON 解析
	data, err := s.parseSubscribeData(decoded)
	if err != nil {
		slog.Error("subscribe data parse failed", "error", err)
		return nil, errs.WithMsg("订阅数据解析失败", errs.ErrInternal)
	}

	// 4. 按 domain 排序后遍历站点并 upsert（确保存储顺序稳定）
	result := &response.SubscribeResultResp{}
	siteNames := make([]string, 0, len(data.ApiSite))
	siteDomain := make(map[string]string)
	for domain, site := range data.ApiSite {
		siteNames = append(siteNames, site.Name)
		siteDomain[site.Name] = domain
	}
	sort.Strings(siteNames)
	order := len(siteNames)
	for index, siteName := range siteNames {
		domain := siteDomain[siteName]
		site := data.ApiSite[domain]
		added, err := s.upsertSite(ctx, domain, site, data.CacheTime, order-index)
		if err != nil {
			slog.Error("upsert site failed", "domain", domain, "error", err)
			continue
		}
		result.Domains = append(result.Domains, domain)
		result.Total++
		if added {
			result.Added++
		} else {
			result.Updated++
		}
	}

	// 5. 清除缓存
	s.clearSiteCache(ctx)

	return result, nil
}

// ListSites 获取资源站点列表（按用户组过滤）
// userID: 当前用户 ID，role: 当前用户角色
func (s *ResourceService) ListSites(ctx context.Context, userID int64, role int8) ([]*response.ResourceSiteResp, error) {
	// 管理员不受用户组限制，返回所有站点
	if entity.Role(role) == entity.RoleAdmin {
		return s.listAllSites(ctx)
	}

	// 普通用户按用户组过滤
	if s.groupService == nil {
		// 未启用用户组功能，返回空列表
		return []*response.ResourceSiteResp{}, nil
	}

	// 获取用户的 group_id
	groupID, err := s.groupService.GetUserGroupID(ctx, userID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	if groupID == nil {
		// 未分配用户组，返回空列表
		return []*response.ResourceSiteResp{}, nil
	}

	// 获取用户组关联的 config_key 列表
	configKeys, err := s.groupService.GetGroupResources(ctx, *groupID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	if len(configKeys) == 0 {
		return []*response.ResourceSiteResp{}, nil
	}

	// 查询数据库中启用的站点
	configs, err := s.configService.ListEnabledByGroup(ctx, configGroupSite)
	if err != nil {
		return nil, err
	}

	// 构建 config_key set 用于快速查找
	keySet := make(map[string]bool, len(configKeys))
	for _, k := range configKeys {
		keySet[k] = true
	}

	// 过滤出用户组关联的站点
	list := make([]*response.ResourceSiteResp, 0)
	for _, cfg := range configs {
		if !keySet[cfg.ConfigKey] {
			continue
		}
		site := &response.ResourceSiteResp{
			Domain:     cfg.ConfigKey,
			Name:       cfg.Title,
			API:        cfg.Value1,
			Detail:     cfg.Value2,
			Comment:    cfg.Value3,
			CacheTime:  parseInt(cfg.Value4),
			IsEnabled:  cfg.IsEnabled,
			IsAdult:    cfg.Value5 == "1",
			Searchable: cfg.Value6 != "0",
		}
		list = append(list, site)
	}

	return list, nil
}

// listAllSites 获取所有启用的资源站点（管理员使用，优先走缓存）
func (s *ResourceService) listAllSites(ctx context.Context) ([]*response.ResourceSiteResp, error) {
	ck := cache.KeyResourceSite()
	val, err := s.cache.Get(ctx, ck.Key)
	if err == nil && val != "" {
		var list []*response.ResourceSiteResp
		if json.Unmarshal([]byte(val), &list) == nil {
			return list, nil
		}
	}

	// 查询数据库
	configs, err := s.configService.ListEnabledByGroup(ctx, configGroupSite)
	if err != nil {
		return nil, err
	}

	list := make([]*response.ResourceSiteResp, 0, len(configs))
	for _, cfg := range configs {
		site := &response.ResourceSiteResp{
			Domain:     cfg.ConfigKey,
			Name:       cfg.Title,
			API:        cfg.Value1,
			Detail:     cfg.Value2,
			Comment:    cfg.Value3,
			CacheTime:  parseInt(cfg.Value4),
			IsEnabled:  cfg.IsEnabled,
			IsAdult:    cfg.Value5 == "1",
			Searchable: cfg.Value6 != "0",
		}
		list = append(list, site)
	}

	// 写入缓存
	if data, e := json.Marshal(list); e == nil {
		_ = s.cache.Set(ctx, ck.Key, string(data), ck.TTL)
	}

	return list, nil
}

// StartCron 启动 cron 定时任务（应用启动时调用）
func (s *ResourceService) StartCron() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	ctx := context.Background()
	cfg := s.configService.GetValue(ctx, configKeySubscribe)
	if cfg == nil {
		slog.Info("resource subscribe config not found, skipping cron")
		return nil
	}

	autoSub := parseBool(cfg.Value2)
	url := cfg.Value1
	cronExpr := cfg.Value3

	if !autoSub || url == "" {
		slog.Info("resource auto-subscribe is disabled or URL is empty")
		return nil
	}

	s.cron = cron.New(cron.WithSeconds())

	entryID, err := s.cron.AddFunc(cronExpr, func() {
		slog.Info("resource subscribe cron triggered")
		_, err := s.FetchAndSaveSites(context.Background())
		if err != nil {
			slog.Error("resource subscribe cron failed", "error", err)
		}
	})
	if err != nil {
		return fmt.Errorf("invalid cron expression %q: %w", cronExpr, err)
	}

	s.cronEntryID = entryID
	s.cron.Start()
	slog.Info("resource subscribe cron started", "cron", cronExpr)

	return nil
}

// StopCron 停止 cron（应用关闭时调用）
func (s *ResourceService) StopCron() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.cron != nil {
		s.cron.Stop()
		slog.Info("resource subscribe cron stopped")
	}
}

// RestartCron 重新注册 cron 任务（配置变更后调用）
func (s *ResourceService) RestartCron() error {
	s.StopCron()
	return s.StartCron()
}

// --- 内部方法 ---

// getHTTPClient 根据代理配置动态返回 HTTP 客户端
func (s *ResourceService) getHTTPClient(ctx context.Context) *http.Client {
	cfg := s.configService.GetValue(ctx, configKeyProxy)
	if cfg != nil && cfg.IsEnabled {
		enabled := parseBool(cfg.Value6)
		if enabled && cfg.Value2 != "" {
			return util.ProxyHTTPClient(cfg.Value1, cfg.Value2, cfg.Value3, cfg.Value4, cfg.Value5, true, 30*time.Second)
		}
	}
	return s.httpClient
}

// fetchSubscribe HTTP GET 订阅地址，返回响应体字符串
func (s *ResourceService) fetchSubscribe(ctx context.Context, url string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", errs.Wrap(err, errs.ErrInternal)
	}

	resp, err := s.getHTTPClient(ctx).Do(req)
	if err != nil {
		slog.Error("fetch subscribe URL failed", "url", url, "error", err)
		return "", errs.WithMsg("订阅地址请求失败", errs.ErrInternal)
	}
	defer func(Body io.ReadCloser) {
		_ = Body.Close()
	}(resp.Body)

	if resp.StatusCode != http.StatusOK {
		return "", errs.WithMsg(fmt.Sprintf("订阅地址返回异常状态码: %d", resp.StatusCode), errs.ErrInternal)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", errs.Wrap(err, errs.ErrInternal)
	}

	return string(bodyBytes), nil
}

// parseSubscribeData 将解码后的字节解析为 subscribeData
func (s *ResourceService) parseSubscribeData(data []byte) (*subscribeData, error) {
	var result subscribeData
	if err := json.Unmarshal(data, &result); err != nil {
		return nil, fmt.Errorf("JSON unmarshal failed: %w", err)
	}
	return &result, nil
}

// upsertSite 插入或更新单个站点记录，返回是否为新增
func (s *ResourceService) upsertSite(ctx context.Context, domain string, site siteItem, cacheTime, index int) (bool, error) {
	existing := s.configService.GetValue(ctx, domain)

	value5 := strconv.Itoa(util.Ternary(strings.HasPrefix(site.Name, "🔞"), 1, 0))
	value6 := strconv.Itoa(util.Ternary(util.NoSearch(site.Comment), 0, 1))
	if existing != nil {
		// 更新
		updateReq := &request.ConfigUpdateReq{
			ConfigKey: domain,
			Title:     &site.Name,
			Value1:    &site.API,
			Value2:    &site.Detail,
			Value3:    &site.Comment,
			Value5:    &value5,
			Value6:    &value6,
		}
		ctStr := strconv.Itoa(cacheTime)
		updateReq.Value4 = &ctStr
		return false, s.configService.Update(ctx, updateReq)
	}

	// 创建
	cfg := &entity.SysConfig{
		ConfigKey:   domain,
		ConfigGroup: configGroupSite,
		Title:       site.Name,
		Title1:      "API地址",
		Value1:      site.API,
		Title2:      "详情地址",
		Value2:      site.Detail,
		Title3:      "备注",
		Value3:      site.Comment,
		Title4:      "缓存时间",
		Value4:      strconv.Itoa(cacheTime),
		Title5:      "18禁",
		Value5:      value5,
		Title6:      "允许搜索",
		Value6:      value6,
		IsEnabled:   true,
		SortOrder:   index,
	}

	return true, s.configService.Create(ctx, &request.ConfigCreateReq{
		ConfigKey:   cfg.ConfigKey,
		ConfigGroup: cfg.ConfigGroup,
		Title:       cfg.Title,
		Title1:      cfg.Title1,
		Title2:      cfg.Title2,
		Title3:      cfg.Title3,
		Title4:      cfg.Title4,
		Title5:      cfg.Title5,
		Title6:      cfg.Title6,
		Value1:      cfg.Value1,
		Value2:      cfg.Value2,
		Value3:      cfg.Value3,
		Value4:      cfg.Value4,
		Value5:      cfg.Value5,
		Value6:      cfg.Value6,
		IsEnabled:   cfg.IsEnabled,
		SortOrder:   index,
	})
}

// clearSiteCache 清除资源站点缓存
func (s *ResourceService) clearSiteCache(ctx context.Context) {
	ck := cache.KeyResourceSite()
	_ = s.cache.Delete(ctx, ck.Key)
	// 也清除 sys_config 组缓存
	_ = s.configService.RefreshCache(ctx)
}

// --- 辅助函数 ---

func parseBool(s string) bool {
	return strings.ToLower(s) == "true" || s == "1" || strings.ToLower(s) == "yes"
}

func parseInt(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}
