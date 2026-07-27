package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
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

// ResourceImageService 资源站图片代理服务（独立于豆瓣图片代理）
type ResourceImageService struct {
	configSvc  *SysConfigService
	cache      cache.Cache
	httpClient *http.Client
	stopCh     chan struct{}
}

// NewResourceImageService 创建资源站图片代理服务
func NewResourceImageService(configSvc *SysConfigService, c cache.Cache) *ResourceImageService {
	return &ResourceImageService{
		configSvc:  configSvc,
		cache:      c,
		httpClient: &http.Client{Timeout: 30 * 1e9}, // 30s
		stopCh:     make(chan struct{}),
	}
}

// ProxyImage 代理资源站图片请求
// URL 格式: /api/resource/image/proxy?url=xxx
func (s *ResourceImageService) ProxyImage(c echo.Context, imageURL string) error {
	ctx := c.Request().Context()

	// 1. 校验 URL 合法性
	if err := s.validateImageURL(imageURL); err != nil {
		return err
	}

	// 2. 检查本地缓存（resource_image_proxy 配置已废弃，始终启用缓存）
	cacheEnabled := true
	if cacheEnabled {
		cached, contentType, err := s.getFromCache(ctx, imageURL)
		if err == nil && cached != nil {
			c.Response().Header().Set("Content-Type", contentType)
			c.Response().Header().Set("Cache-Control", "public, max-age=86400")
			c.Response().Header().Set("X-Image-Cache", "HIT")
			return c.Blob(http.StatusOK, contentType, cached)
		}
	}

	// 3. 远程获取图片（含重试 + 完整性校验，不完整则重试）
	imageData, contentType, err := fetchWithRetry(ctx, slog.Default(), imageURL, func() fetchImageResult {
		data, ct, cl, e := s.fetchImage(ctx, imageURL)
		return fetchImageResult{data: data, contentType: ct, contentLen: cl, err: e}
	})
	if err != nil {
		return errs.WithMsg(fmt.Sprintf("获取图片失败: %v", err), errs.ErrServiceUnavailable)
	}

	// 4. 写入本地缓存
	if cacheEnabled && imageData != nil {
		go s.saveToCache(context.Background(), imageURL, imageData, contentType)
	}

	// 5. 返回图片
	c.Response().Header().Set("Content-Type", contentType)
	c.Response().Header().Set("Cache-Control", "public, max-age=86400")
	c.Response().Header().Set("X-Image-Cache", "MISS")
	return c.Blob(http.StatusOK, contentType, imageData)
}

// validateImageURL 校验图片 URL 合法性
func (s *ResourceImageService) validateImageURL(imageURL string) error {
	parsed, err := url.Parse(imageURL)
	if err != nil {
		return errs.WithMsg("无效的图片 URL", errs.ErrBadRequest)
	}

	if parsed.Scheme != "https" && parsed.Scheme != "http" {
		return errs.WithMsg("仅支持 HTTP/HTTPS 图片 URL", errs.ErrBadRequest)
	}

	return nil
}

// fetchImage 远程获取图片（单次尝试，不重试）
// 返回 contentLength 用于上层重试校验；校验由调用方 fetchWithRetry 统一完成
func (s *ResourceImageService) fetchImage(ctx context.Context, imageURL string) ([]byte, string, int64, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, imageURL, nil)
	if err != nil {
		return nil, "", 0, errs.WithMsg("构建图片请求失败", errs.ErrInternal)
	}

	// 伪装浏览器 Referer，部分资源站防盗链
	req.Header.Set("Referer", imageURL)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		slog.Error("fetch resource image failed", "url", imageURL, "error", err)
		return nil, "", 0, errs.WithMsg("获取图片失败", errs.ErrServiceUnavailable)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		slog.Error("resource image bad status", "url", imageURL, "status", resp.StatusCode)
		return nil, "", 0, errs.WithMsg(fmt.Sprintf("图片源返回异常状态码: %d", resp.StatusCode), errs.ErrServiceUnavailable)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", 0, errs.WithMsg("读取图片数据失败", errs.ErrInternal)
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType == "" || !strings.HasPrefix(contentType, "image/") {
		contentType = "image/jpeg"
	}

	return data, contentType, resp.ContentLength, nil
}

// --- 本地文件缓存 ---

// cacheDir 获取缓存目录（resource_image_proxy 配置已废弃，使用硬编码默认值）
func (s *ResourceImageService) cacheDir(ctx context.Context) string {
	return "./data/resource_images"
}

// cacheDays 获取缓存天数（resource_image_proxy 配置已废弃，使用硬编码默认值 7 天）
func (s *ResourceImageService) cacheDays(ctx context.Context) int {
	return 7
}

// cacheFilePath 生成缓存文件路径
// 格式: {cacheDir}/{YYYY-MM-DD}/{SHA256}.dat
func (s *ResourceImageService) cacheFilePath(ctx context.Context, imageURL string) string {
	hash := sha256.Sum256([]byte(imageURL))
	hashStr := hex.EncodeToString(hash[:])
	dateDir := time.Now().Format("2006-01-02")
	return filepath.Join(s.cacheDir(ctx), dateDir, hashStr+".dat")
}

// cacheMetaPath 生成缓存元数据文件路径
func (s *ResourceImageService) cacheMetaPath(ctx context.Context, imageURL string) string {
	hash := sha256.Sum256([]byte(imageURL))
	hashStr := hex.EncodeToString(hash[:])
	dateDir := time.Now().Format("2006-01-02")
	return filepath.Join(s.cacheDir(ctx), dateDir, hashStr+".meta")
}

// getFromCache 从本地缓存获取图片
func (s *ResourceImageService) getFromCache(ctx context.Context, imageURL string) ([]byte, string, error) {
	filePath := s.cacheFilePath(ctx, imageURL)

	info, err := os.Stat(filePath)
	if err != nil {
		return nil, "", err
	}

	// 检查是否过期
	days := s.cacheDays(ctx)
	if time.Since(info.ModTime()) > time.Duration(days)*24*time.Hour {
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
		slog.Warn("cached resource image corrupted, removed", "path", filePath, "error", err)
		return nil, "", fmt.Errorf("cached image corrupted: %w", err)
	}

	return data, contentType, nil
}

// saveToCache 保存图片到本地缓存
func (s *ResourceImageService) saveToCache(ctx context.Context, imageURL string, data []byte, contentType string) {
	// 防御性校验：仅完整可用的图片才写入缓存
	if err := validateImage(data); err != nil {
		slog.Warn("skip caching corrupted resource image", "url", imageURL, "error", err)
		return
	}

	filePath := s.cacheFilePath(ctx, imageURL)

	dir := filepath.Dir(filePath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		slog.Error("failed to create resource image cache dir", "dir", dir, "error", err)
		return
	}

	if err := os.WriteFile(filePath, data, 0644); err != nil {
		slog.Error("failed to cache resource image", "path", filePath, "error", err)
		return
	}

	metaPath := s.cacheMetaPath(ctx, imageURL)
	_ = os.WriteFile(metaPath, []byte(contentType), 0644)
}

// StartCleanupGoroutine 启动定期缓存清理 goroutine
// 清理间隔固定为 1 小时（resource_image_proxy 配置已废弃）
func (s *ResourceImageService) StartCleanupGoroutine() {
	hours := 1

	go func() {
		ticker := time.NewTicker(time.Duration(hours) * time.Hour)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				s.cleanupExpiredCache()
			case <-s.stopCh:
				slog.Info("resource image cache cleanup goroutine stopped")
				return
			}
		}
	}()

	slog.Info("resource image cache cleanup goroutine started", "interval_hours", hours)
}

// Stop 停止清理 goroutine
func (s *ResourceImageService) Stop() {
	close(s.stopCh)
}

// cleanupExpiredCache 清理过期缓存
func (s *ResourceImageService) cleanupExpiredCache() {
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
		slog.Error("resource image cache cleanup walk error", "error", err)
		return
	}

	// 清理空目录
	cleanEmptyDirs(cacheDir)

	slog.Info("resource image cache cleanup completed",
		"total_files", totalFiles,
		"deleted_files", deletedFiles,
		"expire_days", days,
	)
}
