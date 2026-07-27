package service

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"sync"
	"time"
)

const (
	// configKeyStream 流配置 key
	configKeyStream = "stream_config"
	// streamDirDefault 流临时文件根目录
	streamDirDefault = "data/stream/tmp"
	// cleanupInterval 清理间隔
	cleanupInterval = 60 * time.Second
	// idleExpireTimeout 空闲超时
	idleExpireTimeout = 30 * time.Minute
	// completedIdleTimeout Completed 状态空闲超时（1天，与临时文件保留对齐）
	completedIdleTimeout = 24 * time.Hour
	// completedUserTimeout Completed 状态用户超时（5分钟，容忍前端暂停）
	completedUserTimeout = 5 * time.Minute
)

// StreamService 全局流代理管理器
// sessionCreatingEntry 用于标识 session 正在创建中
// 其他并发请求同一 m3u8 URL 的协程通过等待 done chan 获取结果
type sessionCreatingEntry struct {
	done    chan struct{}
	session *StreamSession
	err     error
}

type StreamService struct {
	parser           *M3u8Parser
	configService    *SysConfigService
	httpClient       *http.Client
	sessions         sync.Map // sessionKey -> *StreamSession
	creatingSessions sync.Map // sessionKey -> *sessionCreatingEntry（创建中的占位符）
	streamDir        string
	stopCh           chan struct{}
	wg               sync.WaitGroup
	config           *StreamConfig
	configMu         sync.RWMutex // 保护 config 的并发读写
	saveCallback     SaveCallback // 自动保存回调
}

// NewStreamService 创建 StreamService
func NewStreamService(configService *SysConfigService, saveCallback SaveCallback) *StreamService {
	s := &StreamService{
		configService: configService,
		httpClient:    &http.Client{Timeout: 60 * time.Second},
		stopCh:        make(chan struct{}),
		saveCallback:  saveCallback,
	}

	// 初始化 parser
	s.parser = NewM3u8Parser(s.httpClient)

	// 读取配置
	s.config = s.loadConfig()

	// 设置流临时目录
	s.streamDir = streamDirDefault
	if s.config != nil {
		// 可以通过配置覆盖默认目录
	}

	return s
}

// loadConfig 加载流配置
func (s *StreamService) loadConfig() *StreamConfig {
	cfg := s.configService.GetValue(context.Background(), configKeyStream)
	if cfg == nil {
		return DefaultStreamConfig()
	}

	config := &StreamConfig{}

	// Value1: buffer_size
	if cfg.Value1 != "" {
		if v, err := strconv.Atoi(cfg.Value1); err == nil {
			config.BufferSize = v
		}
	}
	if config.BufferSize == 0 {
		config.BufferSize = 20
	}

	// Value2: general_workers
	if cfg.Value2 != "" {
		if v, err := strconv.Atoi(cfg.Value2); err == nil {
			config.GeneralWorkers = v
		}
	}
	if config.GeneralWorkers == 0 {
		config.GeneralWorkers = 5
	}

	// Value3: max_workers
	if cfg.Value3 != "" {
		if v, err := strconv.Atoi(cfg.Value3); err == nil {
			config.MaxWorkers = v
		}
	}
	if config.MaxWorkers == 0 {
		config.MaxWorkers = 8
	}

	// Value4: auto_save
	if cfg.Value4 != "" {
		config.AutoSave = cfg.Value4 == "1" || cfg.Value4 == "true"
	}

	// Value5: is_enable
	if cfg.Value5 != "" {
		config.IsEnable = cfg.Value5 == "1" || cfg.Value5 == "true"
	}

	// Value6: max_disk_cache_mb
	if cfg.Value6 != "" {
		if v, err := strconv.Atoi(cfg.Value6); err == nil {
			config.MaxDiskCacheMB = v
		}
	}
	if config.MaxDiskCacheMB == 0 {
		config.MaxDiskCacheMB = 10240 // 默认 10GB
	}

	return config
}

// Start 启动 StreamService
func (s *StreamService) Start() {
	slog.Info("stream service starting")

	// 创建流临时目录
	if err := os.MkdirAll(s.streamDir, 0755); err != nil {
		slog.Error("failed to create stream dir", "dir", s.streamDir, "error", err)
	}

	// 启动后台清理协程
	s.wg.Add(1)
	go s.cleanupLoop()

	slog.Info("stream service started",
		"stream_dir", s.streamDir,
		"config", s.config)
}

// Stop 停止 StreamService
func (s *StreamService) Stop() {
	slog.Info("stream service stopping...")
	close(s.stopCh)

	// 停止所有 session
	s.sessions.Range(func(key, value interface{}) bool {
		session := value.(*StreamSession)
		session.Stop()
		session.Cleanup(true) // 保留磁盘缓存，由 LRU 清理策略管理
		return true
	})

	s.wg.Wait()
	slog.Info("stream service stopped")
}

// cleanupLoop 后台清理协程主循环
func (s *StreamService) cleanupLoop() {
	defer s.wg.Done()

	ticker := time.NewTicker(cleanupInterval)
	defer ticker.Stop()

	for {
		select {
		case <-s.stopCh:
			return
		case <-ticker.C:
			s.cleanup()
		}
	}
}

// cleanup 执行清理
func (s *StreamService) cleanup() {
	now := time.Now()

	// 1. 清理 Session
	s.sessions.Range(func(key, value interface{}) bool {
		session := value.(*StreamSession)

		// 跳过正在保存中的 Session（由 OnSessionComplete 处理关闭）
		if session.GetState() == SessionStateSaving {
			return true
		}

		// 检查是否空闲超时
		if session.GetState() == SessionStateIdle {
			lastAccess := session.GetLastAccess()
			if now.Sub(lastAccess) > idleExpireTimeout {
				slog.Info("cleaning up idle session",
					"session_key", session.GetSessionKey(),
					"last_access", lastAccess)

				session.Stop()
				session.Cleanup(true) // 保留磁盘缓存，由 LRU 清理策略管理
				s.sessions.Delete(key)
			}
			return true
		}

		// Completed 状态：等待所有客户端观看完成后关闭
		if session.GetState() == SessionStateCompleted {
			users := session.GetAllUsers()

			// 移除超时用户（30秒未报告），同时记录活跃用户信息
			hasActiveUser := false
			var earliestIndex int = -1
			for _, user := range users {
				if now.Sub(user.LastReport) > 30*time.Second {
					session.RemoveUser(user.UserID)
				} else {
					hasActiveUser = true
					if earliestIndex < 0 || user.CurrentIndex < earliestIndex {
						earliestIndex = user.CurrentIndex
					}
				}
			}

			// 根据用户状态决定下一步
			if !hasActiveUser {
				// 无活跃用户，检查是否需要清理
				users = session.GetAllUsers()
				lastAccess := session.GetLastAccess()
				if len(users) == 0 {
					// 无用户，检查空闲超时
					if now.Sub(lastAccess) > completedIdleTimeout {
						slog.Info("cleaning up completed session (no users, idle timeout)",
							"session_key", session.GetSessionKey(),
							"last_access", lastAccess)
						session.Stop()
						session.Cleanup(true)
						s.sessions.Delete(key)
					}
				} else {
					// 所有用户都超时了但还没删除（边界情况），使用 completedUserTimeout
					if now.Sub(lastAccess) > completedUserTimeout {
						slog.Info("cleaning up completed session (users inactive)",
							"session_key", session.GetSessionKey(),
							"last_access", lastAccess)
						session.Stop()
						session.Cleanup(true)
						s.sessions.Delete(key)
					}
				}
			} else {
				// 有活跃用户，滑动窗口向最早用户位置靠拢
				session.GetCacheManager().SlideWindow(earliestIndex)
			}
			return true
		}

		// 非 Idle/Completed 状态（如 Active）：检查用户超时
		users := session.GetAllUsers()
		for _, user := range users {
			if now.Sub(user.LastReport) > 30*time.Second {
				session.RemoveUser(user.UserID)
			}
		}

		return true
	})

	// 2. 清理磁盘缓存（基于存储上限 LRU 策略）
	s.cleanupDiskCache(now)
}

// cacheDirInfo 缓存目录信息（用于 LRU 排序）
type cacheDirInfo struct {
	name      string
	modTime   time.Time
	sizeBytes int64
}

// cleanupDiskCache 基于存储上限的 LRU 磁盘缓存清理
// 当缓存总大小超过 maxDiskCacheMB 时，按最后修改时间排序，淘汰最久未访问的缓存目录
// 同时清理活跃 Session 正在使用的目录（跳过）
func (s *StreamService) cleanupDiskCache(now time.Time) {
	s.configMu.RLock()
	maxMB := s.config.MaxDiskCacheMB
	s.configMu.RUnlock()

	if maxMB <= 0 {
		// 不限制磁盘缓存，跳过清理
		return
	}

	maxBytes := int64(maxMB) * 1024 * 1024

	entries, err := os.ReadDir(s.streamDir)
	if err != nil {
		return
	}

	// 收集所有缓存目录信息，排除活跃 Session 正在使用的目录
	activeDirs := make(map[string]bool)
	s.sessions.Range(func(key, value interface{}) bool {
		session := value.(*StreamSession)
		activeDirs[filepath.Base(session.GetSegmentDir())] = true
		return true
	})

	var dirs []cacheDirInfo
	var totalSize int64

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		// 跳过活跃 Session 正在使用的目录
		if activeDirs[entry.Name()] {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		dirSize := calcDirSize(filepath.Join(s.streamDir, entry.Name()))
		totalSize += dirSize
		dirs = append(dirs, cacheDirInfo{
			name:      entry.Name(),
			modTime:   info.ModTime(),
			sizeBytes: dirSize,
		})
	}

	// 未超限，无需清理
	if totalSize <= maxBytes {
		slog.Debug("disk cache within limit",
			"total_mb", totalSize/1024/1024,
			"limit_mb", maxMB)
		return
	}

	// 按修改时间升序排序（最久未访问的在前，优先淘汰）
	sort.Slice(dirs, func(i, j int) bool {
		return dirs[i].modTime.Before(dirs[j].modTime)
	})

	// 淘汰直到低于上限的 80%（避免频繁清理）
	targetBytes := int64(float64(maxBytes) * 0.8)
	evicted := 0

	for _, dir := range dirs {
		if totalSize <= targetBytes {
			break
		}

		dirPath := filepath.Join(s.streamDir, dir.name)
		if err := os.RemoveAll(dirPath); err != nil {
			slog.Warn("failed to cleanup disk cache dir",
				"dir", dirPath,
				"error", err)
		} else {
			slog.Info("cleaned up disk cache dir (LRU)",
				"dir", dir.name,
				"size_mb", dir.sizeBytes/1024/1024,
				"last_access", dir.modTime.Format(time.DateTime))
			totalSize -= dir.sizeBytes
			evicted++
		}
	}

	if evicted > 0 {
		slog.Info("disk cache cleanup completed",
			"evicted", evicted,
			"total_mb", totalSize/1024/1024,
			"limit_mb", maxMB)
	}
}

// calcDirSize 计算目录大小（递归累加所有文件大小）
func calcDirSize(dirPath string) int64 {
	var size int64
	entries, err := os.ReadDir(dirPath)
	if err != nil {
		return 0
	}
	for _, entry := range entries {
		if entry.IsDir() {
			size += calcDirSize(filepath.Join(dirPath, entry.Name()))
		} else {
			info, err := entry.Info()
			if err == nil {
				size += info.Size()
			}
		}
	}
	return size
}

// GetOrCreateSession 查找已有 session 或创建新 session
// 使用 singleflight 模式防止并发创建重复 session
// m3u8 解析在锁外执行，相同 URL 的并发请求等待结果而非阻塞
func (s *StreamService) GetOrCreateSession(m3u8URL string) (*StreamSession, error) {
	sessionKey := GenerateSessionKey(m3u8URL)

	// 快速路径：查找已有 session（无锁）
	if existing, ok := s.sessions.Load(sessionKey); ok {
		session := existing.(*StreamSession)
		session.refreshLastAccess()
		return session, nil
	}

	// 尝试注册为创建者：使用 sync.Map 的原子操作
	entry := &sessionCreatingEntry{
		done: make(chan struct{}),
	}

	// LoadOrStore：如果已有其他协程在创建，返回已有的 entry
	if actual, loaded := s.creatingSessions.LoadOrStore(sessionKey, entry); loaded {
		// 另一个协程正在创建，等待其完成
		existingEntry := actual.(*sessionCreatingEntry)
		<-existingEntry.done
		if existingEntry.err != nil {
			return nil, existingEntry.err
		}
		existingEntry.session.refreshLastAccess()
		return existingEntry.session, nil
	}

	// 本协程是创建者，在锁外执行耗时的 m3u8 解析
	session, err := NewStreamSession(m3u8URL, s.parser, s.httpClient, s.streamDir)

	if err != nil {
		entry.err = err
		s.creatingSessions.Delete(sessionKey)
		close(entry.done)
		return nil, err
	}

	// 设置回调链：CacheManager.onAllDone -> Session.onComplete -> Service.OnSessionComplete
	session.cacheManager.SetOnAllDone(func() {
		if session.onComplete != nil {
			session.onComplete(session.sessionKey)
		}
	})
	session.SetOnComplete(func(sessionKey string) {
		s.OnSessionComplete(sessionKey)
	})

	// 检查是否所有分片已通过磁盘缓存恢复完成
	// 如果是，Session 直接进入 Completed 状态，无需启动调度器下载
	if session.cacheManager.IsAllDone() {
		session.setState(SessionStateCompleted)
		slog.Info("session restored from disk cache, all segments already done",
			"session_key", sessionKey,
			"total_segments", session.cacheManager.TotalSegments())
	} else {
		// 部分或全部分片需要下载，创建并启动调度中心
		s.configMu.RLock()
		scheduler := NewScheduleCenter(session, s.config)
		s.configMu.RUnlock()
		session.Start(scheduler)
		scheduler.Start()
	}

	// 存储 session 并清理创建占位符
	s.sessions.Store(sessionKey, session)
	entry.session = session
	s.creatingSessions.Delete(sessionKey)
	close(entry.done)

	return session, nil
}

// GetSession 按 sessionKey 查找
func (s *StreamService) GetSession(sessionKey string) (*StreamSession, bool) {
	val, ok := s.sessions.Load(sessionKey)
	if !ok {
		return nil, false
	}
	return val.(*StreamSession), true
}

// ProxyM3U8 代理 m3u8，返回重写后的内容和会话 key
// token 参数用于在 TS/Key URL 中嵌入认证信息，支持无法设置自定义 HTTP 头的客户端（如 Apple TV AVPlayer）
// token 为空时，TS/Key URL 不包含 token 参数，客户端需通过 Authorization 头认证
func (s *StreamService) ProxyM3U8(m3u8URL string, token string) ([]byte, string, error) {
	session, err := s.GetOrCreateSession(m3u8URL)
	if err != nil {
		return nil, "", err
	}
	return session.GetRewrittenM3U8(token), session.GetSessionKey(), nil
}

// ProxySegment 代理 TS 分片
// 返回: data（分片数据）, isStreaming（是否需要流式推送）, error
func (s *StreamService) ProxySegment(sessionKey string, segmentIndex int) ([]byte, bool, error) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return nil, false, fmt.Errorf("session not found: %s", sessionKey)
	}

	// 续期 Session 的最后访问时间
	session.refreshLastAccess()

	cacheManager := session.GetCacheManager()

	// 检查分片状态
	status := cacheManager.GetStatus(segmentIndex)
	if status == SegmentStatusDone {
		// 已完成，直接返回
		data, err := cacheManager.GetSegmentData(segmentIndex)
		return data, false, err
	}

	// 未完成，返回 nil 表示需要流式推送
	return nil, true, nil
}

// SubscribeSegment 订阅分片流式推送
func (s *StreamService) SubscribeSegment(sessionKey string, segmentIndex int) (chan []byte, chan struct{}, error) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return nil, nil, fmt.Errorf("session not found: %s", sessionKey)
	}

	// 续期 Session 的最后访问时间
	session.refreshLastAccess()

	return session.GetCacheManager().SubscribeSegment(segmentIndex)
}

// UnsubscribeSegment 取消订阅分片流式推送
func (s *StreamService) UnsubscribeSegment(sessionKey string, segmentIndex int, dataCh chan []byte) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return
	}

	session.GetCacheManager().UnsubscribeSegment(segmentIndex, dataCh)
}

// ProxyKey 代理 AES-128 解密 key
// 播放器通过重写后的 EXT-X-KEY URI 请求解密 key
// keyuri: 原始 key URI（URL 编码后的）
func (s *StreamService) ProxyKey(sessionKey string, keyURI string) ([]byte, error) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return nil, fmt.Errorf("session not found: %s", sessionKey)
	}

	// 续期 Session 的最后访问时间
	session.refreshLastAccess()

	// 从 m3u8Info 的加密信息中查找已缓存的 key
	m3u8Info := session.GetM3U8Info()

	// 检查全局加密 key
	if m3u8Info.Encryption != nil && m3u8Info.Encryption.KeyURI == keyURI && len(m3u8Info.Encryption.Key) > 0 {
		return m3u8Info.Encryption.Key, nil
	}

	// 检查分片级加密 key
	for _, seg := range m3u8Info.Segments {
		if seg.Encryption != nil && seg.Encryption.KeyURI == keyURI && len(seg.Encryption.Key) > 0 {
			return seg.Encryption.Key, nil
		}
	}

	// key 未缓存（理论上不应发生，因为 m3u8 解析时已获取所有 key）
	// 兜底：直接从原始 URI 下载 key
	slog.Warn("encryption key not cached, fetching from original URI",
		"session_key", sessionKey,
		"key_uri", keyURI)

	key, err := s.parser.fetchEncryptionKey(keyURI)
	if err != nil {
		return nil, fmt.Errorf("fetch encryption key: %w", err)
	}

	return key, nil
}

// NotifyUrgentSegment 通知调度器某个分片需要优先下载
// 当前端请求的分片尚未下载时，由 ProxyTS handler 调用，兜底保障 seek 后的快速响应
func (s *StreamService) NotifyUrgentSegment(sessionKey string, segmentIndex int) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return
	}

	// 通过 scheduler 接口通知调度器
	if session.scheduler != nil {
		if sc, ok := session.scheduler.(*ScheduleCenter); ok {
			sc.NotifyUrgentSegment(segmentIndex)
		}
	}
}

// NotifySeek 通知调度器发生了 seek，立即触发任务队列重排
// targetIndex: seek 目标分片索引
// 调度器会中断专属 Worker 的无关任务，以 targetIndex 为中心重新安排下载优先级
func (s *StreamService) NotifySeek(sessionKey string, targetIndex int) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return
	}

	if session.scheduler != nil {
		if sc, ok := session.scheduler.(*ScheduleCenter); ok {
			sc.NotifySeek(targetIndex)
		}
	}
}

// RecordSegmentRequest 记录播放器实际请求的分片索引，用于即时 seek 检测
// 由 ProxyTS handler 调用，相比 UpdateProgress 的周期性上报，能更早检测到 seek
func (s *StreamService) RecordSegmentRequest(sessionKey string, userID int64, segmentIndex int) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return
	}

	// 续期 Session 的最后访问时间
	session.refreshLastAccess()

	session.RecordSegmentRequest(userID, segmentIndex)
}

// UpdateProgress 更新用户播放进度
func (s *StreamService) UpdateProgress(userID int64, sessionKey string, currentIndex, bufferedAhead int, vodID int64, vodName, vodPic, resourceDomain, resourceName, groupKey string, sourceIndex, epIndex int, epName string) error {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return fmt.Errorf("session not found: %s", sessionKey)
	}

	session.UpdateProgress(userID, currentIndex, bufferedAhead, vodID, vodName, vodPic, resourceDomain, resourceName, groupKey, sourceIndex, epIndex, epName)
	return nil
}

// OnSessionComplete 所有分片下载完成时的回调
func (s *StreamService) OnSessionComplete(sessionKey string) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		slog.Warn("session not found for onSessionComplete", "session_key", sessionKey)
		return
	}

	// 设置状态为 Completed（所有分片下载完成，继续服务客户端）
	session.setState(SessionStateCompleted)

	// 停止调度中心（不再需要下载 Worker，但保留用户和缓存）
	session.StopScheduler()

	// 获取 vodInfo 和用户列表
	vodInfo, hasVodInfo := session.GetVodInfo()
	users := session.GetAllUsers()
	var userID int64
	if len(users) > 0 {
		userID = users[0].UserID
	}

	// 补全 m3u8URL（Session 级别信息）
	if vodInfo != nil {
		vodInfo.M3u8URL = session.GetM3U8URL()
	}

	// 获取当前配置
	s.configMu.RLock()
	autoSave := s.config.AutoSave
	s.configMu.RUnlock()

	// 如果开启了自动保存且有 vodInfo，执行保存
	if autoSave && hasVodInfo && s.saveCallback != nil {
		session.setState(SessionStateSaving)
		taskID, err := s.saveCallback.SaveFromStream(
			sessionKey,
			session.GetSegmentDir(),
			session.GetTotalSegments(),
			userID,
			vodInfo,
			session.GetM3U8Info(),
		)
		session.setState(SessionStateCompleted)
		if err != nil {
			slog.Warn("auto save failed",
				"session_key", sessionKey,
				"vod_id", vodInfo.VodID,
				"error", err)
		} else {
			slog.Info("auto save completed",
				"session_key", sessionKey,
				"task_id", taskID)
		}
	}

	// Completed 后滑动窗口淘汰内存缓存（磁盘已有完整数据）
	if len(users) > 0 {
		session.GetCacheManager().SlideWindow(users[0].CurrentIndex)
	} else {
		// 无用户，全量淘汰内存缓存
		session.GetCacheManager().SlideWindow(-1)
	}

	// 不再调用 CloseSession！
	// 依赖 cleanupLoop 在所有用户超时后清理
	slog.Info("session completed, waiting for clients to finish",
		"session_key", sessionKey,
		"user_count", session.GetUserCount())
}

// SaveAsDownload 将临时缓存转为完整下载任务（手动保存接口）
func (s *StreamService) SaveAsDownload(userID int64, sessionKey string, vodID int64, vodName, epName string) (int64, error) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return 0, fmt.Errorf("session not found: %s", sessionKey)
	}

	// 检查是否所有分片都已下载
	cacheManager := session.GetCacheManager()
	if !cacheManager.IsAllDone() {
		return 0, fmt.Errorf("not all segments downloaded: %d/%d",
			cacheManager.GetDoneCount(), cacheManager.TotalSegments())
	}

	// 通过 saveCallback 执行保存
	if s.saveCallback == nil {
		return 0, fmt.Errorf("save callback not configured")
	}

	vodInfo, _ := session.GetVodInfo()
	// 补全 m3u8URL（Session 级别信息）
	if vodInfo != nil {
		vodInfo.M3u8URL = session.GetM3U8URL()
	}

	return s.saveCallback.SaveFromStream(
		sessionKey,
		session.GetSegmentDir(),
		session.GetTotalSegments(),
		userID,
		vodInfo,
		session.GetM3U8Info(),
	)
}

// CloseSession 关闭指定 session
func (s *StreamService) CloseSession(sessionKey string) error {
	session, ok := s.sessions.LoadAndDelete(sessionKey)
	if !ok {
		return fmt.Errorf("session not found: %s", sessionKey)
	}

	sess := session.(*StreamSession)
	sess.Stop()
	sess.Cleanup(true) // 保留磁盘缓存，由 LRU 清理策略管理

	slog.Info("session closed", "session_key", sessionKey)
	return nil
}

// GetStreamDir 获取流临时文件目录
func (s *StreamService) GetStreamDir() string {
	return s.streamDir
}

// GetConfig 获取流配置
func (s *StreamService) GetConfig() *StreamConfig {
	s.configMu.RLock()
	defer s.configMu.RUnlock()
	return s.config
}

// ReloadConfig 重新加载流配置（热更新回调）
func (s *StreamService) ReloadConfig() {
	newConfig := s.loadConfig()
	s.configMu.Lock()
	s.config = newConfig
	s.configMu.Unlock()
	slog.Info("stream config reloaded", "config", s.config)
}

// AddUser 添加用户到 session
func (s *StreamService) AddUser(sessionKey string, userID int64) (*UserProgress, error) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return nil, fmt.Errorf("session not found: %s", sessionKey)
	}

	return session.AddUser(userID), nil
}

// RemoveUser 从 session 移除用户
func (s *StreamService) RemoveUser(sessionKey string, userID int64) {
	session, ok := s.GetSession(sessionKey)
	if !ok {
		return
	}

	session.RemoveUser(userID)
}

// CheckUrlResult 单个 URL 检测结果（导出供 handler 使用）
type CheckUrlResult struct {
	URL        string
	Available  bool
	StatusCode int
	ErrMsg     string
}

// checkUrlWithFallback 检测单个 URL，先尝试 HEAD，失败时降级到 GET
func checkUrlWithFallback(targetURL string, client *http.Client) CheckUrlResult {
	result := CheckUrlResult{URL: targetURL}

	// 1. 先尝试 HEAD 请求
	req, err := http.NewRequest(http.MethodHead, targetURL, nil)
	if err != nil {
		result.Available = false
		result.ErrMsg = fmt.Sprintf("invalid url: %s", err.Error())
		return result
	}

	resp, err := client.Do(req)
	if err == nil {
		defer resp.Body.Close()
		result.StatusCode = resp.StatusCode

		// HEAD 成功：判断状态码
		if resp.StatusCode >= 200 && resp.StatusCode < 400 {
			result.Available = true
			return result
		}

		// 405 Method Not Allowed 时降级到 GET
		if resp.StatusCode == 405 {
			// 继续降级到 GET
		} else {
			// 其他错误状态码（如 404、500 等）直接返回不可用
			result.Available = false
			result.ErrMsg = fmt.Sprintf("HTTP %d", resp.StatusCode)
			return result
		}
	}
	// err != nil 或 405 错误，都降级到 GET 请求

	// 2. 降级到 GET 请求（只读取前 4KB 内容，节省带宽）
	reqGet, err := http.NewRequest(http.MethodGet, targetURL, nil)
	if err != nil {
		result.Available = false
		result.ErrMsg = fmt.Sprintf("invalid url: %s", err.Error())
		return result
	}
	// 设置 Range 只获取前 4KB，判断文件是否存在且可读
	reqGet.Header.Set("Range", "bytes=0-4095")

	respGet, err := client.Do(reqGet)
	if err != nil {
		result.Available = false
		result.ErrMsg = err.Error()
		return result
	}
	defer respGet.Body.Close()

	result.StatusCode = respGet.StatusCode

	// 判断 GET 请求结果：2xx 或 416 Range Not Satisfiable（文件存在但小于请求范围）都算可用
	if respGet.StatusCode >= 200 && respGet.StatusCode < 400 {
		result.Available = true
	} else if respGet.StatusCode == 416 {
		// 416 表示 Range 不满足但文件存在（文件很小），也算可用
		result.Available = true
	} else {
		result.Available = false
		result.ErrMsg = fmt.Sprintf("HTTP %d", respGet.StatusCode)
	}

	return result
}

// CheckM3U8Urls 批量检测 m3u8 链接可用性
// 使用 HEAD 请求并发检测，收到 405 时降级到 GET，最多 10 个并发
func (s *StreamService) CheckM3U8Urls(urls []string) []CheckUrlResult {
	const maxConcurrency = 10
	const checkTimeout = 10 * time.Second

	results := make([]CheckUrlResult, len(urls))
	semaphore := make(chan struct{}, maxConcurrency)
	var wg sync.WaitGroup

	for i, url := range urls {
		wg.Add(1)
		go func(idx int, targetURL string) {
			defer wg.Done()

			// 获取信号量
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			// 创建带超时的 client（不跟随重定向）
			client := &http.Client{
				Timeout: checkTimeout,
				CheckRedirect: func(req *http.Request, via []*http.Request) error {
					// 不跟随重定向，最多返回 3xx 状态码
					return http.ErrUseLastResponse
				},
			}

			results[idx] = checkUrlWithFallback(targetURL, client)
		}(i, url)
	}

	wg.Wait()
	return results
}
