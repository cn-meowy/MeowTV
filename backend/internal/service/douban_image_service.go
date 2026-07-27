package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
)

// DoubanImageService 图片代理服务
type DoubanImageService struct {
	client    *DoubanClient
	configSvc *SysConfigService
	cache     cache.Cache
	stopCh    chan struct{}
}

// NewDoubanImageService 创建图片代理服务
func NewDoubanImageService(client *DoubanClient, configSvc *SysConfigService, cache cache.Cache) *DoubanImageService {
	return &DoubanImageService{
		client:    client,
		configSvc: configSvc,
		cache:     cache,
		stopCh:    make(chan struct{}),
	}
}

// ProxyImage 代理图片请求（token 验证已由 TempTokenAuth 中间件完成）
func (s *DoubanImageService) ProxyImage(c echo.Context, imageURL string) error {
	ctx := c.Request().Context()

	// 1. 校验 URL 合法性
	if err := s.validateImageURL(ctx, imageURL); err != nil {
		return err
	}

	// 3. 检查本地缓存
	cacheEnabled := s.configSvc.GetBool(ctx, "douban_image_proxy", 1)
	if cacheEnabled {
		cached, contentType, err := s.getFromCache(ctx, imageURL)
		if err == nil && cached != nil {
			c.Response().Header().Set("Content-Type", contentType)
			c.Response().Header().Set("Cache-Control", "public, max-age=86400")
			c.Response().Header().Set("X-Image-Cache", "HIT")
			return c.Blob(http.StatusOK, contentType, cached)
		}
	}

	// 4. 尝试图片分流节点获取
	imageData, contentType, err := s.fetchViaImageNode(ctx, imageURL)
	if err != nil {
		return err
	}

	// 5. 写入本地缓存
	if cacheEnabled && imageData != nil {
		go s.saveToCache(context.Background(), imageURL, imageData, contentType)
	}

	// 6. 返回图片
	c.Response().Header().Set("Content-Type", contentType)
	c.Response().Header().Set("Cache-Control", "public, max-age=86400")
	c.Response().Header().Set("X-Image-Cache", "MISS")
	return c.Blob(http.StatusOK, contentType, imageData)
}

// validateImageURL 校验图片 URL 是否在白名单内
func (s *DoubanImageService) validateImageURL(ctx context.Context, imageURL string) error {
	parsed, err := url.Parse(imageURL)
	if err != nil {
		return errs.WithMsg("无效的图片 URL", errs.ErrBadRequest)
	}

	// 必须是 HTTPS
	if parsed.Scheme != "https" && parsed.Scheme != "http" {
		return errs.WithMsg("仅支持 HTTP/HTTPS 图片 URL", errs.ErrBadRequest)
	}

	// 检查 CDN 白名单
	whitelistJSON := s.configSvc.GetString(ctx, "douban_image_proxy", 5)
	if whitelistJSON == "" {
		return nil // 未配置白名单则不限制
	}

	var whitelist []string
	if err := json.Unmarshal([]byte(whitelistJSON), &whitelist); err != nil {
		slog.Warn("failed to parse CDN whitelist", "error", err)
		return nil // 白名单解析失败不阻止请求
	}

	host := parsed.Hostname()
	allowed := false
	for _, w := range whitelist {
		if host == w || strings.HasSuffix(host, "."+w) {
			allowed = true
			break
		}
	}

	if !allowed {
		return errs.WithMsg(fmt.Sprintf("图片域名 %s 不在允许的白名单内", host), errs.ErrForbidden)
	}

	return nil
}

// fetchViaImageNode 通过图片分流节点获取图片
// 优先根据图片URL域名精确匹配对应节点，匹配失败则按优先级尝试所有节点
// 每个节点内部通过 fetchWithRetry 进行重试 + 完整性校验，仍失败再回退下一节点
func (s *DoubanImageService) fetchViaImageNode(ctx context.Context, imageURL string) ([]byte, string, error) {
	nodes := s.client.GetImageNodes(ctx)
	parsed, _ := url.Parse(imageURL)
	host := parsed.Hostname()
	logger := slog.Default()

	// makeFetchFn 构造单次获取闭包：FetchImage 内部已校验，contentLen 传 -1 跳过长度比对
	makeFetchFn := func(targetURL string) func() fetchImageResult {
		return func() fetchImageResult {
			data, contentType, err := s.client.FetchImage(ctx, targetURL)
			return fetchImageResult{data: data, contentType: contentType, contentLen: -1, err: err}
		}
	}

	// 1. 精确匹配：根据图片URL域名找到对应分流节点配置
	for _, node := range nodes {
		if !node.Enabled || node.BaseURL == "" {
			continue
		}
		nodeParsed, _ := url.Parse(node.BaseURL)
		if nodeParsed.Hostname() == host {
			// 域名匹配，重试获取
			data, contentType, err := fetchWithRetry(ctx, logger, imageURL, makeFetchFn(imageURL))
			if err == nil && len(data) > 0 {
				slog.Debug("image fetched via matched node", "node", node.NodeKey, "url", imageURL)
				return data, contentType, nil
			}
			slog.Warn("matched node failed after retries, trying fallback", "node", node.NodeKey, "error", err)
			break
		}
	}

	// 2. 回退：按优先级尝试所有启用的节点（替换域名）
	for _, node := range nodes {
		if !node.Enabled || node.BaseURL == "" {
			continue
		}

		nodeURL, err := s.replaceHost(imageURL, parsed, node.BaseURL)
		if err != nil {
			continue
		}

		data, contentType, err := fetchWithRetry(ctx, logger, nodeURL, makeFetchFn(nodeURL))
		if err == nil && len(data) > 0 {
			slog.Debug("image fetched via fallback node", "node", node.NodeKey, "url", nodeURL)
			return data, contentType, nil
		}

		slog.Warn("node failed after retries, trying next",
			"node", node.NodeKey,
			"node_url", nodeURL,
			"error", err,
		)
	}

	// 3. 所有节点失败，直连回源 + 重试
	data, contentType, err := fetchWithRetry(ctx, logger, imageURL, makeFetchFn(imageURL))
	if err != nil {
		return nil, "", errs.WithMsg("所有图片通道均不可用", errs.ErrServiceUnavailable)
	}

	return data, contentType, nil
}

// replaceHost 替换图片 URL 的域名为分流节点域名
func (s *DoubanImageService) replaceHost(originalURL string, parsed *url.URL, cdnBase string) (string, error) {
	cdnParsed, err := url.Parse(cdnBase)
	if err != nil {
		return "", err
	}
	newURL := *parsed
	newURL.Scheme = cdnParsed.Scheme
	newURL.Host = cdnParsed.Host
	return newURL.String(), nil
}

// --- 本地文件缓存 ---

// cacheDir 获取缓存目录
func (s *DoubanImageService) cacheDir(ctx context.Context) string {
	dir := s.configSvc.GetString(ctx, "douban_image_proxy", 2)
	if dir == "" {
		dir = "./data/douban_images"
	}
	return dir
}

// cacheDays 获取缓存天数
func (s *DoubanImageService) cacheDays(ctx context.Context) int {
	days := s.configSvc.GetInt(ctx, "douban_image_proxy", 3)
	if days <= 0 {
		days = 7
	}
	return days
}

// cacheFilePath 生成缓存文件路径
// 格式: {cacheDir}/{YYYY-MM-DD}/{SHA256}.dat
func (s *DoubanImageService) cacheFilePath(ctx context.Context, imageURL string) string {
	hash := sha256.Sum256([]byte(imageURL))
	hashStr := hex.EncodeToString(hash[:])
	dateDir := time.Now().Format("2006-01-02")
	return filepath.Join(s.cacheDir(ctx), dateDir, hashStr+".dat")
}

// cacheMetaPath 生成缓存元数据文件路径
func (s *DoubanImageService) cacheMetaPath(ctx context.Context, imageURL string) string {
	hash := sha256.Sum256([]byte(imageURL))
	hashStr := hex.EncodeToString(hash[:])
	dateDir := time.Now().Format("2006-01-02")
	return filepath.Join(s.cacheDir(ctx), dateDir, hashStr+".meta")
}

// getFromCache 从本地缓存获取图片
func (s *DoubanImageService) getFromCache(ctx context.Context, imageURL string) ([]byte, string, error) {
	filePath := s.cacheFilePath(ctx, imageURL)

	info, err := os.Stat(filePath)
	if err != nil {
		return nil, "", err
	}

	// 检查是否过期
	days := s.cacheDays(ctx)
	if time.Since(info.ModTime()) > time.Duration(days)*24*time.Hour {
		// 过期删除
		_ = os.Remove(filePath)
		_ = os.Remove(s.cacheMetaPath(ctx, imageURL))
		return nil, "", fmt.Errorf("cache expired")
	}

	data, err := os.ReadFile(filePath)
	if err != nil {
		return nil, "", err
	}

	// 读取 Content-Type
	metaPath := s.cacheMetaPath(ctx, imageURL)
	contentType := "image/jpeg"
	metaData, err := os.ReadFile(metaPath)
	if err == nil && string(metaData) != "" {
		contentType = string(metaData)
	}

	// 校验缓存图片完整性，损坏则删除坏缓存并回退到重新获取
	if err := validateImage(data); err != nil {
		_ = os.Remove(filePath)
		_ = os.Remove(s.cacheMetaPath(ctx, imageURL))
		slog.Warn("cached image corrupted, removed", "path", filePath, "error", err)
		return nil, "", fmt.Errorf("cached image corrupted: %w", err)
	}

	return data, contentType, nil
}

// saveToCache 保存图片到本地缓存
func (s *DoubanImageService) saveToCache(ctx context.Context, imageURL string, data []byte, contentType string) {
	// 防御性校验：仅完整可用的图片才写入缓存
	if err := validateImage(data); err != nil {
		slog.Warn("skip caching corrupted image", "url", imageURL, "error", err)
		return
	}

	filePath := s.cacheFilePath(ctx, imageURL)

	// 确保目录存在
	dir := filepath.Dir(filePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		slog.Error("failed to create cache dir", "dir", dir, "error", err)
		return
	}

	// 写入图片数据
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		slog.Error("failed to cache image", "path", filePath, "error", err)
		return
	}

	// 写入 Content-Type 元数据
	metaPath := s.cacheMetaPath(ctx, imageURL)
	_ = os.WriteFile(metaPath, []byte(contentType), 0644)
}

// StartCleanupGoroutine 启动定期缓存清理 goroutine
func (s *DoubanImageService) StartCleanupGoroutine() {
	hours := s.configSvc.GetInt(context.Background(), "douban_image_proxy", 4)
	if hours <= 0 {
		hours = 1
	}

	go func() {
		ticker := time.NewTicker(time.Duration(hours) * time.Hour)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				s.cleanupExpiredCache()
			case <-s.stopCh:
				slog.Info("image cache cleanup goroutine stopped")
				return
			}
		}
	}()

	slog.Info("image cache cleanup goroutine started", "interval_hours", hours)
}

// Stop 停止清理 goroutine
func (s *DoubanImageService) Stop() {
	close(s.stopCh)
}

// cleanupExpiredCache 清理过期缓存
func (s *DoubanImageService) cleanupExpiredCache() {
	ctx := context.Background()
	cacheDir := s.cacheDir(ctx)
	days := s.cacheDays(ctx)
	expireAfter := time.Duration(days) * 24 * time.Hour

	var totalFiles, deletedFiles int

	err := filepath.Walk(cacheDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			return nil
		}

		totalFiles++

		if time.Since(info.ModTime()) > expireAfter {
			if err := os.Remove(path); err == nil {
				deletedFiles++
			}
		}

		return nil
	})

	if err != nil && !os.IsNotExist(err) {
		slog.Error("cache cleanup walk error", "error", err)
		return
	}

	// 清理空目录
	cleanEmptyDirs(cacheDir)

	slog.Info("image cache cleanup completed",
		"total_files", totalFiles,
		"deleted_files", deletedFiles,
		"expire_days", days,
	)
}

// cleanEmptyDirs 清理空目录
func cleanEmptyDirs(root string) {
	_ = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || !info.IsDir() {
			return nil
		}
		// 跳过根目录
		if path == root {
			return nil
		}
		// 尝试删除空目录
		_ = os.Remove(path)
		return nil
	})
}
