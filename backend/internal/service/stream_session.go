package service

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// SessionState 会话状态
type SessionState int

const (
	SessionStateCreated   SessionState = iota // 创建中
	SessionStateActive                        // 活跃
	SessionStateIdle                          // 空闲
	SessionStateSaving                        // 保存中
	SessionStateCompleted                     // 所有分片下载完成，继续服务客户端
	SessionStateExpired                       // 已过期
	SessionStateError                         // 错误
)

func (s SessionState) String() string {
	switch s {
	case SessionStateCreated:
		return "created"
	case SessionStateActive:
		return "active"
	case SessionStateIdle:
		return "idle"
	case SessionStateSaving:
		return "saving"
	case SessionStateCompleted:
		return "completed"
	case SessionStateExpired:
		return "expired"
	case SessionStateError:
		return "error"
	default:
		return "unknown"
	}
}

// SchedulerInterface 调度中心接口（用于延迟初始化避免循环依赖）
type SchedulerInterface interface {
	Stop()
}

// WorkerInterface 工作协程接口
type WorkerInterface interface {
}

// UserProgress 用户播放进度
type UserProgress struct {
	UserID           int64
	CurrentIndex     int             // 当前播放分片索引
	BufferedAhead    int             // 前置缓冲分片数
	LastReport       time.Time       // 上次上报时间
	DedicatedW       WorkerInterface // 专属协程（调度中心管理）
	LastRequestIndex int             // 播放器最近一次请求的分片索引（用于即时 seek 检测）
}

// VodInfo 影视资源完整信息（用于自动保存下载记录）
type VodInfo struct {
	VodID          int64
	VodName        string
	VodPic         string
	ResourceDomain string
	ResourceName   string
	GroupKey       string
	SourceIndex    int
	EpIndex        int
	EpName         string
	M3u8URL        string // Session 级别，在 OnSessionComplete 时填入
}

// StreamSession 每个 m3u8 URL 对应的会话
type StreamSession struct {
	sessionKey   string
	m3u8URL      string
	m3u8Info     *M3u8Info
	cacheManager *SegmentCacheManager
	scheduler    SchedulerInterface // 调度中心（接口，延迟初始化）
	users        sync.Map           // userID -> *UserProgress
	userCount    atomic.Int32
	state        atomic.Int32 // SessionState
	createdAt    time.Time
	lastAccess   int64 // unix timestamp nano
	cancelCtx    context.Context
	cancelFunc   context.CancelFunc
	mu           sync.RWMutex
	segmentDir   string                  // 分片临时目录
	onComplete   func(sessionKey string) // 所有分片完成时的回调
	vodInfo      *VodInfo                // 影视资源完整信息
	hasVodInfo   bool                    // 是否已设置影视信息
}

// GenerateSessionKey 生成会话 key：SHA256(m3u8URL)[:16]
func GenerateSessionKey(m3u8URL string) string {
	hash := sha256.Sum256([]byte(m3u8URL))
	return hex.EncodeToString(hash[:])[:16]
}

// NewStreamSession 创建 StreamSession
// m3u8URL: 原始 m3u8 URL
// parser: M3u8Parser 实例
// httpClient: HTTP 客户端
// streamDir: 临时文件根目录
func NewStreamSession(m3u8URL string, parser *M3u8Parser, httpClient *http.Client, streamDir string) (*StreamSession, error) {
	// 生成会话 key
	sessionKey := GenerateSessionKey(m3u8URL)

	// 解析 m3u8
	m3u8Info, err := parser.Parse(m3u8URL)
	if err != nil {
		return nil, fmt.Errorf("parse m3u8: %w", err)
	}

	// 验证是否为 VOD 流
	if !m3u8Info.IsVOD {
		return nil, fmt.Errorf("only VOD streams are supported (missing EXT-X-ENDLIST)")
	}

	// 创建临时目录
	segmentDir := filepath.Join(streamDir, sessionKey)
	if err := os.MkdirAll(segmentDir, 0755); err != nil {
		return nil, fmt.Errorf("create segment dir: %w", err)
	}

	session := &StreamSession{
		sessionKey: sessionKey,
		m3u8URL:    m3u8URL,
		m3u8Info:   m3u8Info,
		createdAt:  time.Now(),
		segmentDir: segmentDir,
	}

	// 初始化分片缓存管理器
	totalSegments := len(m3u8Info.Segments)
	session.cacheManager = NewSegmentCacheManager(totalSegments, segmentDir)

	// 设置初始状态为 Created
	session.state.Store(int32(SessionStateCreated))
	atomic.StoreInt64(&session.lastAccess, time.Now().UnixNano())

	slog.Info("stream session created",
		"session_key", sessionKey,
		"m3u8_url", m3u8URL,
		"total_segments", totalSegments,
		"duration", m3u8Info.Duration)

	return session, nil
}

// rewriteM3U8 基于原始 m3u8 内容做行级替换
// 规则：
//   - #EXT-X-KEY: 保留，但将 KeyURI 重写为后端代理接口（播放器自行解密）
//   - TS URL（非空且非 # 开头）：替换为 /api/stream/proxy/ts?session=<key>&index=<N>&token=<token>
//   - 其他行：原样保留（包括 EXTINF、EXT-X-DISCONTINUITY、EXT-X-MAP 等）
//
// token 参数用于 Apple TV 等无法设置自定义 HTTP 头的客户端，
// AVPlayer 解析 m3u8 后发起的 TS/Key 子请求会自动携带 URL 中的 token 参数
func (s *StreamSession) rewriteM3U8(info *M3u8Info, sessionKey string, token string) ([]byte, error) {
	var sb strings.Builder
	segIndex := 0

	scanner := bufio.NewScanner(strings.NewReader(info.RawContent))
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		// 重写 EXT-X-KEY 的 URI 属性为后端代理接口
		if strings.HasPrefix(trimmed, "#EXT-X-KEY:") {
			rewrittenKey := s.rewriteExtXKey(trimmed, sessionKey, token)
			sb.WriteString(rewrittenKey + "\n")
			continue
		}

		// 替换 TS URL（非空且非 # 开头）
		if trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			var proxyURL string
			if token != "" {
				proxyURL = fmt.Sprintf("/api/stream/proxy/ts?session=%s&index=%d&token=%s",
					sessionKey, segIndex, token)
			} else {
				proxyURL = fmt.Sprintf("/api/stream/proxy/ts?session=%s&index=%d",
					sessionKey, segIndex)
			}
			sb.WriteString(proxyURL + "\n")
			if segIndex < 3 {
				slog.Debug("rewriteM3U8 segment", "index", segIndex, "originalURL", trimmed, "proxyURL", proxyURL)
			}
			segIndex++
			continue
		}

		// 其他行原样保留
		sb.WriteString(line + "\n")
	}

	slog.Debug("rewriteM3U8 complete", "sessionKey", sessionKey, "totalSegments", segIndex, "totalLength", sb.Len())
	return []byte(sb.String()), nil
}

// rewriteExtXKey 重写 #EXT-X-KEY 行中的 URI 属性为后端代理接口
// 原始: #EXT-X-KEY:METHOD=AES-128,URI="https://key.example.com/key",IV=0x1234
// 重写: #EXT-X-KEY:METHOD=AES-128,URI="/api/stream/proxy/key?session=<key>&keyuri=<encoded>&token=<token>",IV=0x1234
func (s *StreamSession) rewriteExtXKey(line string, sessionKey string, token string) string {
	attrs := parseAttributes(line[len("#EXT-X-KEY:"):])
	keyURI, ok := attrs["URI"]
	if !ok || keyURI == "" {
		// 没有 URI 属性（如 METHOD=NONE），原样返回
		return line
	}

	// 将相对路径 keyURI 解析为绝对 URL，与 m3u8_parser.Parse 中的 EncryptionInfo.KeyURI 保持一致
	// 否则 ProxyKey 匹配时 keyURI="key.key" vs KeyURI="https://example.com/key.key" 不匹配
	absoluteKeyURI := resolveURL(s.m3u8URL, keyURI)

	// 将绝对 KeyURI 编码后作为 query 参数
	var proxyKeyURI string
	if token != "" {
		proxyKeyURI = fmt.Sprintf("/api/stream/proxy/key?session=%s&keyuri=%s&token=%s",
			sessionKey, url.QueryEscape(absoluteKeyURI), token)
	} else {
		proxyKeyURI = fmt.Sprintf("/api/stream/proxy/key?session=%s&keyuri=%s",
			sessionKey, url.QueryEscape(absoluteKeyURI))
	}

	// 在原始行中替换 URI="..." 为代理 URI
	// 匹配 URI="原始值" 并替换为代理值
	oldURIPart := fmt.Sprintf(`URI="%s"`, keyURI)
	newURIPart := fmt.Sprintf(`URI="%s"`, proxyKeyURI)
	result := strings.Replace(line, oldURIPart, newURIPart, 1)

	// 如果精确替换失败（可能引号风格不同），尝试用正则替换
	if result == line {
		// 备选：直接用 parseAttributes 结果重建，按标准属性顺序
		var sb strings.Builder
		sb.WriteString("#EXT-X-KEY:")
		// 按 HLS 标准属性顺序输出
		if method, ok := attrs["METHOD"]; ok {
			sb.WriteString("METHOD=")
			sb.WriteString(method)
		}
		sb.WriteString(fmt.Sprintf(`,URI="%s"`, proxyKeyURI))
		if iv, ok := attrs["IV"]; ok {
			sb.WriteString(",IV=")
			sb.WriteString(iv)
		}
		// 其他未知属性原样追加
		for k, v := range attrs {
			if k == "METHOD" || k == "URI" || k == "IV" {
				continue
			}
			sb.WriteString("," + k + "=" + v)
		}
		result = sb.String()
	}

	return result
}

// GetSessionKey 返回会话 key
func (s *StreamSession) GetSessionKey() string {
	return s.sessionKey
}

// GetM3U8Info 返回 m3u8 解析结果
func (s *StreamSession) GetM3U8Info() *M3u8Info {
	return s.m3u8Info
}

// GetCacheManager 返回分片缓存管理器
func (s *StreamSession) GetCacheManager() *SegmentCacheManager {
	return s.cacheManager
}

// GetRewrittenM3U8 返回重写后的 m3u8 内容
// token 参数用于在 TS/Key URL 中嵌入认证信息，支持无法设置自定义 HTTP 头的客户端（如 Apple TV AVPlayer）
// 每次调用实时重写（m3u8 通常几十 KB，重写耗时 < 1ms）
func (s *StreamSession) GetRewrittenM3U8(token string) []byte {
	s.refreshLastAccess()
	rewritten, err := s.rewriteM3U8(s.m3u8Info, s.sessionKey, token)
	if err != nil {
		// 重写不应失败（只是字符串替换），如果失败返回原始内容作为兜底
		slog.Error("rewrite m3u8 failed in GetRewrittenM3U8", "session_key", s.sessionKey, "error", err)
		return []byte(s.m3u8Info.RawContent)
	}
	return rewritten
}

// AddUser 添加用户到会话
func (s *StreamSession) AddUser(userID int64) *UserProgress {
	// 检查是否已存在
	if existing, ok := s.users.Load(userID); ok {
		up := existing.(*UserProgress)
		up.LastReport = time.Now()
		s.refreshLastAccess()
		return up
	}

	// 创建新的用户进度
	up := &UserProgress{
		UserID:     userID,
		LastReport: time.Now(),
	}
	s.users.Store(userID, up)
	s.userCount.Add(1)
	s.refreshLastAccess()

	// 激活会话
	s.setState(SessionStateActive)

	slog.Info("user added to session",
		"session_key", s.sessionKey,
		"user_id", userID,
		"user_count", s.userCount.Load())

	return up
}

// RemoveUser 从会话移除用户
func (s *StreamSession) RemoveUser(userID int64) {
	if _, ok := s.users.LoadAndDelete(userID); ok {
		s.userCount.Add(-1)
		s.refreshLastAccess()

		slog.Info("user removed from session",
			"session_key", s.sessionKey,
			"user_id", userID,
			"user_count", s.userCount.Load())

		// 如果没有用户了，进入空闲状态
		if s.userCount.Load() == 0 {
			s.setState(SessionStateIdle)
		}
	}
}

// UpdateProgress 更新用户播放进度
func (s *StreamSession) UpdateProgress(userID int64, currentIndex, bufferedAhead int, vodID int64, vodName, vodPic, resourceDomain, resourceName, groupKey string, sourceIndex, epIndex int, epName string) {
	upInterface, ok := s.users.Load(userID)
	if !ok {
		// 用户不存在，先添加
		upInterface = s.AddUser(userID)
	}

	progress := upInterface.(*UserProgress)
	oldIndex := progress.CurrentIndex
	progress.CurrentIndex = currentIndex
	progress.BufferedAhead = bufferedAhead
	progress.LastReport = time.Now()
	s.refreshLastAccess()

	// seek 检测：CurrentIndex 大幅跳变（差值 > 3），视为 seek，立即通知调度器
	indexDelta := currentIndex - oldIndex
	if indexDelta < 0 {
		indexDelta = -indexDelta
	}
	if indexDelta > 3 && s.scheduler != nil {
		if sc, ok := s.scheduler.(*ScheduleCenter); ok {
			sc.NotifySeek(currentIndex)
			slog.Info("seek detected, notifying scheduler",
				"session_key", s.sessionKey,
				"user_id", userID,
				"old_index", oldIndex,
				"new_index", currentIndex,
				"delta", indexDelta)
		}
	}

	// Completed 状态下，滑动窗口跟随播放进度
	if s.GetState() == SessionStateCompleted && currentIndex != oldIndex {
		s.cacheManager.SlideWindow(currentIndex)
	}

	// 首次上报时设置 vodInfo（用于自动保存）
	if !s.hasVodInfo && vodID > 0 && vodName != "" {
		s.SetVodInfo(vodID, vodName, vodPic, resourceDomain, resourceName, groupKey, sourceIndex, epIndex, epName)
	}

	slog.Debug("progress updated",
		"session_key", s.sessionKey,
		"user_id", userID,
		"current_index", currentIndex,
		"buffered_ahead", bufferedAhead,
		"vod_id", vodID)
}

// RecordSegmentRequest 记录播放器实际请求的分片索引，用于即时 seek 检测
// 当播放器请求的分片索引与上次请求索引差值 > 3 时，视为 seek，立即通知调度器重排
// 相比 UpdateProgress 依赖前端周期性上报，本方法通过播放器实际请求行为即时检测 seek
// userID <= 0 表示未认证用户（仅代理透传），不做 seek 检测
func (s *StreamSession) RecordSegmentRequest(userID int64, segmentIndex int) {
	if userID <= 0 {
		return
	}

	upInterface, ok := s.users.Load(userID)
	if !ok {
		// 用户不存在，先添加
		upInterface = s.AddUser(userID)
	}

	progress := upInterface.(*UserProgress)

	// seek 检测：请求分片索引与上次请求差值 > 3
	delta := segmentIndex - progress.LastRequestIndex
	if delta < 0 {
		delta = -delta
	}
	oldRequest := progress.LastRequestIndex
	progress.LastRequestIndex = segmentIndex
	progress.LastReport = time.Now()
	s.refreshLastAccess()

	if delta > 3 && s.scheduler != nil {
		if sc, ok := s.scheduler.(*ScheduleCenter); ok {
			sc.NotifySeek(segmentIndex)
			slog.Info("seek detected by segment request, notifying scheduler",
				"session_key", s.sessionKey,
				"user_id", userID,
				"old_request_index", oldRequest,
				"new_request_index", segmentIndex,
				"delta", delta)
		}
	}

	slog.Debug("segment request recorded",
		"session_key", s.sessionKey,
		"user_id", userID,
		"segment_index", segmentIndex,
		"last_request_index", progress.LastRequestIndex)
}

// GetUser 获取用户进度
func (s *StreamSession) GetUser(userID int64) (*UserProgress, bool) {
	val, ok := s.users.Load(userID)
	if !ok {
		return nil, false
	}
	return val.(*UserProgress), true
}

// GetAllUsers 获取所有用户进度
func (s *StreamSession) GetAllUsers() []*UserProgress {
	users := make([]*UserProgress, 0)
	s.users.Range(func(key, value interface{}) bool {
		users = append(users, value.(*UserProgress))
		return true
	})
	return users
}

// GetUserCount 获取用户数
func (s *StreamSession) GetUserCount() int {
	return int(s.userCount.Load())
}

// GetOrCreateSegment 获取或创建分片缓存条目
func (s *StreamSession) GetOrCreateSegment(index int) (*SegmentCache, bool) {
	return s.cacheManager.GetSegment(index)
}

// GetState 获取会话状态
func (s *StreamSession) GetState() SessionState {
	return SessionState(s.state.Load())
}

// setState 设置会话状态
func (s *StreamSession) setState(state SessionState) {
	s.state.Store(int32(state))
}

// refreshLastAccess 刷新最后访问时间
func (s *StreamSession) refreshLastAccess() {
	atomic.StoreInt64(&s.lastAccess, time.Now().UnixNano())
}

// GetLastAccess 获取最后访问时间
func (s *StreamSession) GetLastAccess() time.Time {
	return time.Unix(0, atomic.LoadInt64(&s.lastAccess))
}

// GetCreatedAt 获取创建时间
func (s *StreamSession) GetCreatedAt() time.Time {
	return s.createdAt
}

// GetTotalSegments 获取总分片数
func (s *StreamSession) GetTotalSegments() int {
	return len(s.m3u8Info.Segments)
}

// GetSegmentDir 获取分片目录
func (s *StreamSession) GetSegmentDir() string {
	return s.segmentDir
}

// GetM3U8URL 获取原始 m3u8 URL
func (s *StreamSession) GetM3U8URL() string {
	return s.m3u8URL
}

// SetVodInfo 设置影视信息（仅首次设置）
func (s *StreamSession) SetVodInfo(vodID int64, vodName, vodPic, resourceDomain, resourceName, groupKey string, sourceIndex, epIndex int, epName string) {
	if s.hasVodInfo || vodID == 0 || vodName == "" {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.hasVodInfo {
		return
	}
	s.vodInfo = &VodInfo{
		VodID:          vodID,
		VodName:        vodName,
		VodPic:         vodPic,
		ResourceDomain: resourceDomain,
		ResourceName:   resourceName,
		GroupKey:       groupKey,
		SourceIndex:    sourceIndex,
		EpIndex:        epIndex,
		EpName:         epName,
	}
	s.hasVodInfo = true
}

// GetVodInfo 获取影视信息
func (s *StreamSession) GetVodInfo() (*VodInfo, bool) {
	return s.vodInfo, s.hasVodInfo
}

// SetOnComplete 设置完成回调
func (s *StreamSession) SetOnComplete(fn func(sessionKey string)) {
	s.onComplete = fn
}

// Start 启动调度中心和工作协程
func (s *StreamSession) Start(scheduler SchedulerInterface) {
	s.scheduler = scheduler
	s.setState(SessionStateActive)
	slog.Info("session started", "session_key", s.sessionKey)
}

// StopScheduler 仅停止调度中心和工作协程，保留用户和缓存
// 用于所有分片下载完成后，不再需要 Worker 但客户端仍在播放的场景
func (s *StreamSession) StopScheduler() {
	if s.scheduler != nil {
		s.scheduler.Stop()
		s.scheduler = nil
	}
	slog.Info("session scheduler stopped", "session_key", s.sessionKey)
}

// Stop 停止调度中心 + 清理所有用户
func (s *StreamSession) Stop() {
	s.StopScheduler()

	// 清理所有用户
	s.users.Range(func(key, _ interface{}) bool {
		s.users.Delete(key)
		return true
	})
	s.userCount.Store(0)

	s.setState(SessionStateExpired)
	slog.Info("session stopped", "session_key", s.sessionKey)
}

// Cleanup 清理临时文件和资源
func (s *StreamSession) Cleanup(keepTempFiles bool) error {
	// 停止调度
	if s.scheduler != nil {
		s.scheduler.Stop()
		s.scheduler = nil
	}

	// 清理用户
	s.users.Range(func(key, _ interface{}) bool {
		s.users.Delete(key)
		return true
	})
	s.userCount.Store(0)

	// 清理临时文件
	if !keepTempFiles && s.segmentDir != "" {
		if err := os.RemoveAll(s.segmentDir); err != nil {
			slog.Warn("failed to cleanup segment dir",
				"session_key", s.sessionKey,
				"dir", s.segmentDir,
				"error", err)
			return err
		}
	}

	slog.Info("session cleaned up", "session_key", s.sessionKey, "kept_files", keepTempFiles)
	return nil
}
