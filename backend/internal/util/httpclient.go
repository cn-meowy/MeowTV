package util

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/proxy"
)

// ProxyHTTPClient 根据代理配置创建 *http.Client
// protocol: http 或 socks5
// host: 代理主机地址
// port: 代理端口
// username: 认证用户名（可选，空字符串表示无认证）
// password: 认证密码（可选，空字符串表示无认证）
// enabled: 是否启用代理
// timeout: 请求超时时间
func ProxyHTTPClient(protocol, host, port, username, password string, enabled bool, timeout time.Duration) *http.Client {
	if !enabled || host == "" {
		return &http.Client{Timeout: timeout}
	}

	protocol = strings.ToLower(strings.TrimSpace(protocol))
	host = strings.TrimSpace(host)
	port = strings.TrimSpace(port)

	switch protocol {
	case "http", "https":
		return newHTTPProxyClient(protocol, host, port, username, password, timeout)
	case "socks5":
		return newSOCKS5ProxyClient(host, port, username, password, timeout)
	default:
		slog.Warn("unsupported proxy protocol, falling back to direct", "protocol", protocol)
		return &http.Client{Timeout: timeout}
	}
}

// newHTTPProxyClient 创建 HTTP/HTTPS 代理客户端
func newHTTPProxyClient(protocol, host, port, username, password string, timeout time.Duration) *http.Client {
	proxyURLStr := fmt.Sprintf("%s://%s", protocol, net.JoinHostPort(host, port))
	proxyURL, err := url.Parse(proxyURLStr)
	if err != nil {
		slog.Error("parse http proxy url failed", "url", proxyURLStr, "error", err)
		return &http.Client{Timeout: timeout}
	}

	// 设置认证信息
	if username != "" {
		proxyURL.User = url.UserPassword(username, password)
	}

	transport := &http.Transport{
		Proxy:           http.ProxyURL(proxyURL),
		TLSClientConfig: &tls.Config{InsecureSkipVerify: false},
	}

	slog.Info("using HTTP proxy", "url", proxyURLStr, "auth", username != "")

	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
	}
}

// newSOCKS5ProxyClient 创建 SOCKS5 代理客户端
func newSOCKS5ProxyClient(host, port, username, password string, timeout time.Duration) *http.Client {
	addr := net.JoinHostPort(host, port)

	var auth *proxy.Auth
	if username != "" {
		auth = &proxy.Auth{
			User:     username,
			Password: password,
		}
	}

	dialer, err := proxy.SOCKS5("tcp", addr, auth, proxy.Direct)
	if err != nil {
		slog.Error("create SOCKS5 dialer failed", "addr", addr, "error", err)
		return &http.Client{Timeout: timeout}
	}

	// proxy.SOCKS5 返回的 dialer 实现了 proxy.ContextDialer 接口
	contextDialer, ok := dialer.(proxy.ContextDialer)
	if !ok {
		slog.Error("SOCKS5 dialer does not support DialContext, falling back to direct")
		return &http.Client{Timeout: timeout}
	}

	transport := &http.Transport{
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			return contextDialer.DialContext(ctx, network, addr)
		},
		TLSClientConfig: &tls.Config{InsecureSkipVerify: false},
	}

	slog.Info("using SOCKS5 proxy", "addr", addr, "auth", username != "")

	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
	}
}

// TestProxyConnectivity 测试代理连通性
// 通过代理访问 testURL 验证代理是否可用
// testURL 为测试目标地址，默认应使用 http://www.gstatic.com/generate_204
// 返回 nil 表示连通，否则返回具体错误信息
func TestProxyConnectivity(protocol, host, port, username, password, testURL string) error {
	if testURL == "" {
		testURL = "http://www.gstatic.com/generate_204"
	}

	client := ProxyHTTPClient(protocol, host, port, username, password, true, 10*time.Second)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, testURL, nil)
	if err != nil {
		return fmt.Errorf("构建测试请求失败: %w", err)
	}

	resp, err := client.Do(req)
	if err != nil {
		// 根据错误类型返回更友好的信息
		errMsg := err.Error()
		if errors.Is(err, context.DeadlineExceeded) {
			return errors.New("代理连接超时 (timeout)")
		}
		if strings.Contains(errMsg, "connection refused") {
			return errors.New("代理服务器拒绝连接 (connection refused)")
		}
		if strings.Contains(errMsg, "no such host") || strings.Contains(errMsg, "lookup") {
			return errors.New("代理地址无法解析 (DNS lookup failed)")
		}
		if strings.Contains(errMsg, "authentication failed") || strings.Contains(errMsg, "auth") {
			return errors.New("代理认证失败 (auth failed)")
		}
		if strings.Contains(errMsg, "i/o timeout") || strings.Contains(errMsg, "TLS handshake") {
			return errors.New("代理连接超时 (timeout)")
		}
		return fmt.Errorf("代理连接失败: %s", errMsg)
	}
	defer func(Body io.ReadCloser) { _ = Body.Close() }(resp.Body)

	// 接受 204 (No Content) 和 200 (OK) 作为成功状态码
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK {
		return fmt.Errorf("代理测试URL返回异常状态码: %d", resp.StatusCode)
	}

	return nil
}
