package service

import (
	"context"
	"log/slog"
	"time"
)

// fetchImageRetryConfig 图片获取重试配置
type fetchImageRetryConfig struct {
	maxRetries int           // 最大重试次数（不含首次尝试）
	baseDelay  time.Duration // 初始退避时长
	maxDelay   time.Duration // 退避上限
}

// defaultFetchRetryConfig 默认重试配置：
// 最多重试 5 次（共 6 次尝试），指数退避 200ms→400ms→800ms→1600ms→3200ms
var defaultFetchRetryConfig = fetchImageRetryConfig{
	maxRetries: 5,
	baseDelay:  200 * time.Millisecond,
	maxDelay:   3200 * time.Millisecond,
}

// fetchImageResult 单次图片获取的结果
type fetchImageResult struct {
	data        []byte
	contentType string
	contentLen  int64 // 响应头声明的 Content-Length，<=0 表示未知
	err         error
}

// fetchWithRetry 对单次图片获取操作进行重试，仅在数据完整可用时返回。
// 每次成功获取后会调用 validateImageWithLength 校验完整性，校验失败也触发重试。
// 指数退避：baseDelay * 2^attempt，封顶 maxDelay。
func fetchWithRetry(
	ctx context.Context,
	logger *slog.Logger,
	url string,
	fetchFn func() fetchImageResult,
) ([]byte, string, error) {
	cfg := defaultFetchRetryConfig
	delay := cfg.baseDelay

	var lastErr error
	for attempt := 0; attempt <= cfg.maxRetries; attempt++ {
		// 重试前退避（首次不退避）
		if attempt > 0 {
			if logger != nil {
				logger.Warn("retrying image fetch",
					"url", url,
					"attempt", attempt,
					"delay", delay,
					"last_error", lastErr,
				)
			}
			select {
			case <-ctx.Done():
				return nil, "", ctx.Err()
			case <-time.After(delay):
			}
			delay *= 2
			if delay > cfg.maxDelay {
				delay = cfg.maxDelay
			}
		}

		res := fetchFn()
		if res.err != nil {
			lastErr = res.err
			continue
		}

		// 校验完整性：contentLen<=0 时仅做解码校验
		if err := validateImageWithLength(res.data, res.contentLen); err != nil {
			lastErr = err
			if logger != nil {
				logger.Warn("image validation failed, will retry",
					"url", url,
					"attempt", attempt,
					"error", err,
				)
			}
			continue
		}

		return res.data, res.contentType, nil
	}

	if lastErr == nil {
		lastErr = ErrImageCorrupted
	}
	return nil, "", lastErr
}
