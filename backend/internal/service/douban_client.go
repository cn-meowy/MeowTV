package service

import (
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"time"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
)

// UA 伪装池 - 常见浏览器 User-Agent
var uaPool = []string{
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
	"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
	"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0",
}

// DoubanClient 豆瓣HTTP客户端
// 负责向豆瓣发起请求，支持多通道切换、限流、UA伪装
type DoubanClient struct {
	httpClient *http.Client
	configSvc  *SysConfigService
	cache      cache.Cache
	limiter    *rateLimiter
}

// rateLimiter 简易令牌桶限流器
type rateLimiter struct {
	ch chan struct{}
}

func newRateLimiter(qps int) *rateLimiter {
	r := &rateLimiter{
		ch: make(chan struct{}, qps),
	}
	// 填充令牌
	for i := 0; i < qps; i++ {
		r.ch <- struct{}{}
	}
	// 按速率补充令牌
	go func() {
		interval := time.Second / time.Duration(qps)
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for range ticker.C {
			select {
			case r.ch <- struct{}{}:
			default:
			}
		}
	}()
	return r
}

func (r *rateLimiter) wait(ctx context.Context) error {
	select {
	case <-r.ch:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

// NewDoubanClient 创建豆瓣客户端
func NewDoubanClient(configSvc *SysConfigService, cache cache.Cache) *DoubanClient {
	qps := configSvc.GetInt(context.Background(), "douban_rate_limit", 1)
	if qps <= 0 {
		qps = 5
	}

	return &DoubanClient{
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
		configSvc: configSvc,
		cache:     cache,
		limiter:   newRateLimiter(qps),
	}
}

// randomUA 随机选择一个 User-Agent
func randomUA() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(int64(len(uaPool))))
	return uaPool[n.Int64()]
}

// FetchJSON 从豆瓣获取 JSON 数据（带缓存 + 多通道 + 限流）
func (c *DoubanClient) FetchJSON(ctx context.Context, doubanPath string, query string) (string, error) {
	// 1. 检查缓存是否启用
	cacheEnabled := c.configSvc.GetBool(ctx, "douban_cache", 2)
	if cacheEnabled {
		cacheKey := cache.KeyDoubanJSON(doubanPath + "?" + query)
		cached, err := c.cache.Get(ctx, cacheKey.Key)
		if err == nil && cached != "" {
			return cached, nil
		}
	}

	// 2. 限流
	if err := c.limiter.wait(ctx); err != nil {
		return "", errs.Wrap(err, errs.ErrTooManyReq)
	}

	// 3. 多通道请求
	result, err := c.fetchWithFallback(ctx, doubanPath, query)
	if err != nil {
		return "", err
	}

	// 4. 写入缓存
	if cacheEnabled {
		cacheKey := cache.KeyDoubanJSON(doubanPath + "?" + query)
		_ = c.cache.Set(ctx, cacheKey.Key, result, cacheKey.TTL)
	}

	return result, nil
}

// fetchWithFallback 多通道请求策略：直连 → Zwei CORS Proxy
func (c *DoubanClient) fetchWithFallback(ctx context.Context, doubanPath string, query string) (string, error) {
	channel := c.configSvc.GetInt(ctx, "douban_json_channel", 3)
	retries := c.configSvc.GetInt(ctx, "douban_json_channel", 5)
	if retries <= 0 {
		retries = 2
	}

	type channelFunc func() (string, error)
	channels := []channelFunc{
		// 通道1：直连豆瓣
		func() (string, error) {
			baseURL := c.configSvc.GetString(ctx, "douban_json_channel", 1)
			if baseURL == "" {
				baseURL = "https://movie.douban.com"
			}
			return c.doRequest(ctx, baseURL, doubanPath, query)
		},
		// 通道2：Zwei CORS Proxy
		func() (string, error) {
			proxyURL := c.configSvc.GetString(ctx, "douban_json_channel", 2)
			if proxyURL == "" {
				return "", fmt.Errorf("CORS proxy not configured")
			}
			targetURL := "https://movie.douban.com" + doubanPath
			if query != "" {
				targetURL += "?" + query
			}
			// Zwei CORS Proxy 格式：proxy_url/target_url
			proxyTarget := proxyURL + "/" + targetURL
			return c.doRawRequest(ctx, proxyTarget)
		},
	}

	// 从当前配置的通道开始尝试
	startIdx := 0
	if channel == 2 {
		startIdx = 1
	}

	var lastErr error
	for attempt := 0; attempt < len(channels); attempt++ {
		idx := (startIdx + attempt) % len(channels)

		for retry := 0; retry <= retries; retry++ {
			result, err := channels[idx]()
			if err == nil {
				return result, nil
			}
			lastErr = err
			slog.Warn("douban channel request failed",
				"channel", idx+1,
				"retry", retry,
				"path", doubanPath,
				"error", err,
			)
		}
	}

	return "", errs.Wrap(lastErr, errs.ErrServiceUnavailable)
}

// doRequest 向指定 baseURL 发起请求
func (c *DoubanClient) doRequest(ctx context.Context, baseURL string, path string, query string) (string, error) {
	u, err := url.Parse(baseURL)
	if err != nil {
		return "", err
	}
	u.Path = path
	if query != "" {
		u.RawQuery = query
	}
	return c.doRawRequest(ctx, u.String())
}

// doRawRequest 发起原始 HTTP 请求
func (c *DoubanClient) doRawRequest(ctx context.Context, targetURL string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, targetURL, nil)
	if err != nil {
		return "", err
	}

	// 设置请求头
	req.Header.Set("User-Agent", randomUA())
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Referer", "https://movie.douban.com/")
	req.Header.Set("Origin", "https://movie.douban.com")

	timeout := c.configSvc.GetInt(ctx, "douban_json_channel", 4)
	if timeout <= 0 {
		timeout = 10
	}
	c.httpClient.Timeout = time.Duration(timeout) * time.Second

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", errs.Wrapf(err, 502, "豆瓣请求失败: %s", targetURL)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", errs.Newf(resp.StatusCode, "豆瓣返回错误: status=%d, body=%s", resp.StatusCode, string(body[:min(len(body), 200)]))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", errs.Wrap(err, errs.ErrInternal)
	}

	return string(body), nil
}

// FetchImage 获取图片二进制数据（用于图片代理）
func (c *DoubanClient) FetchImage(ctx context.Context, imageURL string) ([]byte, string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, imageURL, nil)
	if err != nil {
		return nil, "", err
	}

	req.Header.Set("User-Agent", randomUA())
	req.Header.Set("Referer", "https://movie.douban.com/")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, "", errs.Wrapf(err, 502, "图片请求失败: %s", imageURL)
	}
	defer func(Body io.ReadCloser) {
		_ = Body.Close()
	}(resp.Body)

	if resp.StatusCode != http.StatusOK {
		return nil, "", errs.Newf(resp.StatusCode, "图片返回错误: status=%d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", errs.Wrap(err, errs.ErrInternal)
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "image/jpeg"
	}

	// 校验图片完整性：解码校验 + Content-Length 比对，不完整则返回错误触发上层重试
	if err := validateImageWithLength(body, resp.ContentLength); err != nil {
		return nil, "", fmt.Errorf("%w: %s", ErrImageCorrupted, err)
	}

	return body, contentType, nil
}

// GetImageNodes 获取已启用的图片分流节点列表（按优先级排序）
func (c *DoubanClient) GetImageNodes(ctx context.Context) []ImageNode {
	group, err := c.configSvc.ListEnabledByGroup(ctx, "douban")
	if err != nil {
		return nil
	}

	var nodes []ImageNode
	for _, cfg := range group {
		if strings.HasPrefix(cfg.ConfigKey, "douban_image_node_") {
			// 从 config_key 提取节点标识，如 douban_image_node_img9 -> img9
			nodeKey := strings.TrimPrefix(cfg.ConfigKey, "douban_image_node_")
			priority := c.configSvc.GetInt(ctx, cfg.ConfigKey, 2)
			if priority <= 0 {
				priority = 99
			}
			enabled := c.configSvc.GetBool(ctx, cfg.ConfigKey, 4)
			nodes = append(nodes, ImageNode{
				NodeKey:  nodeKey,
				Name:     cfg.Title,
				BaseURL:  cfg.Value1,
				Priority: priority,
				Enabled:  enabled,
			})
		}
	}

	// 按优先级排序
	for i := 0; i < len(nodes); i++ {
		for j := i + 1; j < len(nodes); j++ {
			if nodes[i].Priority > nodes[j].Priority {
				nodes[i], nodes[j] = nodes[j], nodes[i]
			}
		}
	}

	return nodes
}

// ImageNode 图片分流节点定义
type ImageNode struct {
	NodeKey  string // 节点标识：img1/img2/img3/img9
	Name     string // 显示名称
	BaseURL  string // 节点前缀 URL
	Priority int    // 优先级
	Enabled  bool   // 是否启用
}

// min 返回两个整数中的较小值
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
