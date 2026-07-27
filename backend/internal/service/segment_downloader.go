package service

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
)

const (
	// MaxSegmentRetries 单个分片最大重试次数
	MaxSegmentRetries = 3
	// DefaultSegmentTimeout 单个分片下载超时
	DefaultSegmentTimeout = 60
)

// DownloadOneSegment 下载单个 TS 分片（支持 AES-128 解密，含重试机制）
// httpClient: HTTP 客户端（可传入自定义超时配置）
// segURL: 分片 URL
// enc: 加密信息（nil 表示未加密）
// segIndex: 分片索引（用于日志和 IV 计算）
func DownloadOneSegment(ctx context.Context, httpClient *http.Client, segURL string, enc *EncryptionInfo, segIndex int) ([]byte, error) {
	var lastErr error
	for attempt := 1; attempt <= MaxSegmentRetries; attempt++ {
		data, err := DoDownloadSegment(ctx, httpClient, segURL, enc, segIndex)
		if err == nil {
			return data, nil
		}
		lastErr = err

		// 根据错误类型决定是否重试
		if IsRetryableError(err) {
			slog.Warn("download attempt failed, retrying",
				"segment", segIndex,
				"attempt", attempt,
				"max_retries", MaxSegmentRetries,
				"error", err,
				"url", segURL)
			continue
		}

		// 非重试错误，直接返回
		return nil, fmt.Errorf("segment %d: %w", segIndex, err)
	}

	// 所有重试都失败
	slog.Error("segment download exhausted retries",
		"segment", segIndex,
		"max_retries", MaxSegmentRetries,
		"last_error", lastErr,
		"url", segURL)
	return nil, fmt.Errorf("segment %d: exceeded max retries %d: %w", segIndex, MaxSegmentRetries, lastErr)
}

// DoDownloadSegment 执行单次分片下载（不含重试逻辑）
// httpClient: HTTP 客户端
// segURL: 分片 URL
// enc: 加密信息（nil 表示未加密）
// segIndex: 分片索引（用于日志和 IV 计算）
func DoDownloadSegment(ctx context.Context, httpClient *http.Client, segURL string, enc *EncryptionInfo, segIndex int) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, segURL, nil)
	if err != nil {
		return nil, err
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	slog.Debug("segment downloaded",
		"segment", segIndex,
		"bytes", len(data),
		"url", segURL)

	// AES-128 解密
	if enc != nil && enc.Method == "AES-128" && len(enc.Key) > 0 {
		iv := enc.IV
		if len(iv) == 0 {
			// 使用分片序号作为 IV
			iv = make([]byte, 16)
			iv[15] = byte(segIndex)
		}
		decrypted, decryptErr := DecryptSegment(data, enc.Key, iv)
		if decryptErr != nil {
			// 解密失败：检查原始数据是否为未加密的 TS 流
			// 某些视频源在 m3u8 中声明了 AES-128 加密，但分片实际未加密
			if IsTSPacketData(data) {
				slog.Warn("segment decrypt failed but data looks like unencrypted TS, using raw data",
					"segment", segIndex,
					"decrypt_error", decryptErr,
					"data_bytes", len(data),
					"url", segURL)
				return data, nil
			}
			slog.Warn("segment decrypt failed",
				"segment", segIndex,
				"data_bytes", len(data),
				"iv_len", len(iv),
				"key_len", len(enc.Key),
				"error", decryptErr,
				"url", segURL)
			return nil, fmt.Errorf("decrypt failed: %w", decryptErr)
		}
		data = decrypted
	}

	return data, nil
}

// IsRetryableError 判断错误是否可重试（网络截断、超时等临时性错误）
func IsRetryableError(err error) bool {
	if err == nil {
		return false
	}
	errStr := err.Error()
	retryablePatterns := []string{
		"not a multiple of block size", // 数据截断导致长度不对
		"input data is empty",          // 空响应
		"less than block size",         // 数据过短
		"pkcs7 unpadding failed",       // padding 错误可能由网络截断导致
		"invalid padding",              // 同上
		"connection reset",             // 连接重置
		"connection refused",           // 连接被拒绝
		"timeout",                      // 超时
		"temporary failure",            // 临时失败
		"i/o timeout",                  // I/O 超时
		"ECONNRESET",                   // 连接重置
		"ECONNREFUSED",                 // 连接被拒绝
	}
	for _, pattern := range retryablePatterns {
		if strings.Contains(errStr, pattern) {
			return true
		}
	}
	return false
}
