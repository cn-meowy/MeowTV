package service

import (
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"sync"
	"sync/atomic"
	"time"
)

// ErrSegmentExpired 分片已过期（磁盘文件已清理）
var ErrSegmentExpired = fmt.Errorf("segment file expired")

// SegmentStatus 分片下载状态
type SegmentStatus int

const (
	SegmentStatusPending     SegmentStatus = iota // 等待下载
	SegmentStatusDownloading                      // 下载中
	SegmentStatusDone                             // 下载完成
	SegmentStatusFailed                           // 下载失败
)

func (s SegmentStatus) String() string {
	switch s {
	case SegmentStatusPending:
		return "pending"
	case SegmentStatusDownloading:
		return "downloading"
	case SegmentStatusDone:
		return "done"
	case SegmentStatusFailed:
		return "failed"
	default:
		return "unknown"
	}
}

// SegmentCache 分片缓存条目
type SegmentCache struct {
	index      int
	status     SegmentStatus
	mu         sync.RWMutex
	data       []byte        // 完成后的完整数据（内存热缓存）
	filePath   string        // 磁盘文件路径
	consumers  []chan []byte // 流式推送消费者列表（每个消费者一个 channel）
	doneCh     chan struct{} // 分片下载完成信号
	lastAccess int64         // 上次访问时间（用于 LRU）
}

// newSegmentCache 创建分片缓存条目
func newSegmentCache(index int) *SegmentCache {
	return &SegmentCache{
		index:     index,
		status:    SegmentStatusPending,
		consumers: make([]chan []byte, 0),
		doneCh:    make(chan struct{}),
	}
}

// SegmentCacheManager 分片缓存管理器（双层缓存 + 流式推送消费者管理）
type SegmentCacheManager struct {
	totalSegments int
	segmentDir    string
	segments      sync.Map // index -> *SegmentCache
	doneCount     atomic.Int32
	memLimit      int          // 内存缓存上限，默认 200
	memUsed       atomic.Int32 // 当前内存缓存数量
	onAllDone     func()       // 所有分片完成回调
	allDoneOnce   sync.Once    // 确保 onAllDone 只触发一次
}

// segFileRegex 匹配分片文件名格式 seg_XXXX.ts
var segFileRegex = regexp.MustCompile(`^seg_(\d+)\.ts$`)

// NewSegmentCacheManager 创建分片缓存管理器
// totalSegments: 总分片数
// segmentDir: 分片文件存储目录
// 会扫描 segmentDir 中已有的分片文件，将存在的分片直接标记为 Done（磁盘缓存恢复）
func NewSegmentCacheManager(totalSegments int, segmentDir string) *SegmentCacheManager {
	m := &SegmentCacheManager{
		totalSegments: totalSegments,
		segmentDir:    segmentDir,
		memLimit:      200,
	}

	// 初始化所有分片为 Pending 状态
	for i := 0; i < totalSegments; i++ {
		m.segments.Store(i, newSegmentCache(i))
	}

	// 扫描磁盘目录，恢复已有的分片文件
	m.restoreFromDisk()

	return m
}

// restoreFromDisk 扫描 segmentDir 目录，将已存在的分片文件标记为 Done
// 这样 B 用户播放同一视频时可以直接复用 A 用户已下载的磁盘缓存，无需重新下载
func (m *SegmentCacheManager) restoreFromDisk() {
	entries, err := os.ReadDir(m.segmentDir)
	if err != nil {
		// 目录不存在或无权限，跳过恢复
		return
	}

	restored := 0
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		// 解析文件名 seg_XXXX.ts -> index
		matches := segFileRegex.FindStringSubmatch(entry.Name())
		if len(matches) != 2 {
			continue
		}

		index, err := strconv.Atoi(matches[1])
		if err != nil || index < 0 || index >= m.totalSegments {
			continue
		}

		// 获取文件信息，验证文件非空
		info, err := entry.Info()
		if err != nil || info.Size() == 0 {
			continue
		}

		// 将该分片标记为 Done，记录 filePath
		seg, ok := m.segments.Load(index)
		if !ok {
			continue
		}

		cacheEntry := seg.(*SegmentCache)
		cacheEntry.mu.Lock()
		if cacheEntry.status == SegmentStatusPending {
			cacheEntry.status = SegmentStatusDone
			cacheEntry.filePath = filepath.Join(m.segmentDir, entry.Name())
			cacheEntry.lastAccess = time.Now().UnixNano()
			// 注意：不从磁盘读取 data 到内存，按需回填（GetSegmentData 的磁盘 fallback 会处理）
		}
		cacheEntry.mu.Unlock()

		m.doneCount.Add(1)
		restored++
	}

	if restored > 0 {
		slog.Info("restored segments from disk cache",
			"segment_dir", m.segmentDir,
			"restored", restored,
			"total", m.totalSegments)
	}
}

// GetSegment 获取分片缓存条目
func (m *SegmentCacheManager) GetSegment(index int) (*SegmentCache, bool) {
	val, ok := m.segments.Load(index)
	if !ok {
		return nil, false
	}
	return val.(*SegmentCache), true
}

// GetStatus 获取分片状态
func (m *SegmentCacheManager) GetStatus(index int) SegmentStatus {
	seg, ok := m.GetSegment(index)
	if !ok {
		return SegmentStatusPending
	}
	seg.mu.RLock()
	defer seg.mu.RUnlock()
	return seg.status
}

// SetStatus 设置分片状态
func (m *SegmentCacheManager) SetStatus(index int, status SegmentStatus) {
	seg, ok := m.GetSegment(index)
	if !ok {
		return
	}
	seg.mu.Lock()
	seg.status = status
	seg.mu.Unlock()
}

// SetOnAllDone 设置所有分片完成时的回调
// 如果在设置回调时所有分片已通过磁盘缓存恢复完成，立即触发回调
func (m *SegmentCacheManager) SetOnAllDone(fn func()) {
	m.onAllDone = fn

	// 磁盘缓存恢复可能在 SetOnAllDone 之前完成（restoreFromDisk 在 NewSegmentCacheManager 中执行）
	// 此时 onAllDone 为 nil 不会被触发，需要在此补偿检查
	// 使用 allDoneOnce 确保回调只触发一次（避免与 MarkSegmentDone 中的触发重复）
	if m.IsAllDone() && fn != nil {
		go m.allDoneOnce.Do(fn)
	}
}

// GetSegmentData 获取已完成分片数据（优先内存，fallback 磁盘）
func (m *SegmentCacheManager) GetSegmentData(index int) ([]byte, error) {
	seg, ok := m.GetSegment(index)
	if !ok {
		return nil, fmt.Errorf("segment %d not found", index)
	}

	seg.mu.Lock()
	defer seg.mu.Unlock()

	// 已完成且内存有数据，直接返回
	if seg.status == SegmentStatusDone && seg.data != nil {
		atomic.StoreInt64(&seg.lastAccess, time.Now().UnixNano())
		return seg.data, nil
	}

	// 内存没有，尝试从磁盘读取
	if seg.filePath != "" {
		// 检查文件是否还存在
		if _, err := os.Stat(seg.filePath); os.IsNotExist(err) {
			// 文件已被清理，返回过期错误
			return nil, ErrSegmentExpired
		}
		data, err := os.ReadFile(seg.filePath)
		if err == nil {
			// 回填内存缓存（在同一个 Lock 下完成，避免竞争窗口）
			if seg.data == nil && m.memUsed.Load() < int32(m.memLimit) {
				seg.data = data
				m.memUsed.Add(1)
			}
			atomic.StoreInt64(&seg.lastAccess, time.Now().UnixNano())
			return data, nil
		}
		return nil, fmt.Errorf("read segment file: %w", err)
	}

	return nil, fmt.Errorf("segment %d not ready", index)
}

// SubscribeSegment 订阅分片流式推送
// 返回: dataCh (接收数据 chunks), doneCh (下载完成信号), 错误
func (m *SegmentCacheManager) SubscribeSegment(index int) (chan []byte, chan struct{}, error) {
	seg, ok := m.GetSegment(index)
	if !ok {
		return nil, nil, fmt.Errorf("segment %d not found", index)
	}

	seg.mu.Lock()
	defer seg.mu.Unlock()

	// 如果已完成，直接返回已完成信号
	if seg.status == SegmentStatusDone {
		doneCh := make(chan struct{})
		close(doneCh)
		return nil, doneCh, nil
	}

	// 创建消费者 channel（buffer 500 chunks × 32KB ≈ 16MB，足够缓冲一个 TS 分片）
	dataCh := make(chan []byte, 500)
	seg.consumers = append(seg.consumers, dataCh)

	return dataCh, seg.doneCh, nil
}

// UnsubscribeSegment 取消订阅分片流式推送
func (m *SegmentCacheManager) UnsubscribeSegment(index int, dataCh chan []byte) {
	seg, ok := m.GetSegment(index)
	if !ok {
		return
	}

	seg.mu.Lock()
	defer seg.mu.Unlock()

	// 从消费者列表中移除
	for i, ch := range seg.consumers {
		if ch == dataCh {
			seg.consumers = append(seg.consumers[:i], seg.consumers[i+1:]...)
			close(ch)
			break
		}
	}
}

// MarkSegmentDone 标记分片下载完成，写入磁盘，通知所有消费者
func (m *SegmentCacheManager) MarkSegmentDone(index int, data []byte) error {
	seg, ok := m.GetSegment(index)
	if !ok {
		return fmt.Errorf("segment %d not found", index)
	}

	seg.mu.Lock()
	defer seg.mu.Unlock()

	// 已经完成，直接返回
	if seg.status == SegmentStatusDone {
		return nil
	}

	// 写入磁盘
	segPath := filepath.Join(m.segmentDir, fmt.Sprintf("seg_%04d.ts", index))
	if err := os.WriteFile(segPath, data, 0644); err != nil {
		seg.status = SegmentStatusFailed
		return fmt.Errorf("write segment file: %w", err)
	}
	seg.filePath = segPath
	seg.data = data
	seg.status = SegmentStatusDone

	// 更新完成计数
	m.doneCount.Add(1)

	// 通知所有消费者
	// 对于已有流式消费者的分片（未加密分片通过 BroadcastChunk 逐块推送过数据），
	// 只关闭 channel 通知完成，不再发送完整数据（避免重复推送）
	// 对于没有通过 BroadcastChunk 推送过的消费者（如加密分片），关闭 channel 即可
	// 消费者通过 doneCh 信号知道分片已完成，可再次请求完整数据
	for _, ch := range seg.consumers {
		close(ch)
	}
	seg.consumers = nil

	// 更新内存缓存计数
	if m.memUsed.Load() < int32(m.memLimit) {
		m.memUsed.Add(1)
	} else {
		// 超出限制，不缓存到内存
		seg.data = nil
	}

	slog.Debug("segment done",
		"index", index,
		"bytes", len(data),
		"done_count", m.doneCount.Load(),
		"mem_used", m.memUsed.Load())

	// 检查所有分片是否完成，触发 onAllDone 回调（sync.Once 确保只触发一次）
	if m.IsAllDone() && m.onAllDone != nil {
		fn := m.onAllDone
		go m.allDoneOnce.Do(fn)
	}

	return nil
}

// MarkSegmentFailed 标记分片下载失败
func (m *SegmentCacheManager) MarkSegmentFailed(index int) {
	seg, ok := m.GetSegment(index)
	if !ok {
		return
	}

	seg.mu.Lock()
	defer seg.mu.Unlock()

	seg.status = SegmentStatusFailed

	// 通知所有消费者连接断开
	for _, ch := range seg.consumers {
		close(ch)
	}
	seg.consumers = nil
}

// ResetDownloadingToPending 将 Downloading 状态的分片重置为 Pending
// 用于 Worker 任务被取消时，将分片状态恢复为 Pending，避免状态泄漏
// 仅当当前状态为 Downloading 时才重置，避免影响已完成或已失败的分片
func (m *SegmentCacheManager) ResetDownloadingToPending(index int) {
	seg, ok := m.GetSegment(index)
	if !ok {
		return
	}

	seg.mu.Lock()
	defer seg.mu.Unlock()

	if seg.status == SegmentStatusDownloading {
		seg.status = SegmentStatusPending
		slog.Debug("reset downloading segment to pending",
			"index", index)
	}
}

// IsAllDone 检查所有分片是否完成
func (m *SegmentCacheManager) IsAllDone() bool {
	return int(m.doneCount.Load()) == m.totalSegments
}

// GetDoneCount 获取已完成分片数
func (m *SegmentCacheManager) GetDoneCount() int {
	return int(m.doneCount.Load())
}

// GetPendingSegments 获取未完成分片列表
func (m *SegmentCacheManager) GetPendingSegments() []int {
	pending := make([]int, 0, m.totalSegments)
	for i := 0; i < m.totalSegments; i++ {
		status := m.GetStatus(i)
		if status == SegmentStatusPending || status == SegmentStatusFailed {
			pending = append(pending, i)
		}
	}
	return pending
}

// GetDownloadingSegments 获取正在下载的分片列表
func (m *SegmentCacheManager) GetDownloadingSegments() []int {
	downloading := make([]int, 0)
	for i := 0; i < m.totalSegments; i++ {
		if m.GetStatus(i) == SegmentStatusDownloading {
			downloading = append(downloading, i)
		}
	}
	return downloading
}

// BroadcastChunk 广播 chunk 数据给所有消费者（用于流式推送）
// 阻塞等待消费者消费，确保数据不丢失
func (m *SegmentCacheManager) BroadcastChunk(index int, chunk []byte) {
	seg, ok := m.GetSegment(index)
	if !ok {
		return
	}

	seg.mu.RLock()
	consumers := make([]chan []byte, len(seg.consumers))
	copy(consumers, seg.consumers)
	seg.mu.RUnlock()

	for _, ch := range consumers {
		ch <- chunk // 阻塞等待消费者消费，确保数据不丢失
	}
}

// EvictMemoryCache LRU 淘汰超出 memLimit 的内存缓存
func (m *SegmentCacheManager) EvictMemoryCache() {
	if m.memUsed.Load() <= int32(m.memLimit) {
		return
	}

	// 收集所有有内存缓存的分片
	type segWithAccess struct {
		index      int
		lastAccess int64
	}
	segments := make([]segWithAccess, 0)

	m.segments.Range(func(key, value interface{}) bool {
		seg := value.(*SegmentCache)
		seg.mu.RLock()
		if seg.data != nil && seg.status == SegmentStatusDone {
			segments = append(segments, segWithAccess{
				index:      seg.index,
				lastAccess: atomic.LoadInt64(&seg.lastAccess),
			})
		}
		seg.mu.RUnlock()
		return true
	})

	// 按 lastAccess 升序排序（最久未使用的在前）
	sort.Slice(segments, func(i, j int) bool {
		return segments[i].lastAccess < segments[j].lastAccess
	})

	// 淘汰直到低于限制
	targetCount := int32(m.memLimit / 2) // 淘汰到限制的一半
	evicted := 0

	for _, sa := range segments {
		if m.memUsed.Load() <= targetCount {
			break
		}

		seg, ok := m.GetSegment(sa.index)
		if !ok {
			continue
		}

		seg.mu.Lock()
		if seg.data != nil {
			seg.data = nil
			m.memUsed.Add(-1)
			evicted++
			slog.Debug("evicted memory cache",
				"index", sa.index,
				"mem_used", m.memUsed.Load())
		}
		seg.mu.Unlock()
	}

	if evicted > 0 {
		slog.Info("evicted memory cache", "count", evicted, "mem_used", m.memUsed.Load())
	}
}

// SlideWindow 滑动窗口内存缓存管理
// centerIndex: 当前播放位置的分片索引
// 保留 [centerIndex-windowBefore, centerIndex+windowAfter] 在内存
// 淘汰窗口外的分片（seg.data = nil），下次访问时从磁盘回填
// 如果 centerIndex < 0，则淘汰所有内存缓存
func (m *SegmentCacheManager) SlideWindow(centerIndex int) {
	windowBefore := 3
	windowAfter := 5

	var windowStart, windowEnd int
	if centerIndex < 0 {
		// 全量淘汰模式
		windowStart = m.totalSegments
		windowEnd = -1
	} else {
		windowStart = centerIndex - windowBefore
		if windowStart < 0 {
			windowStart = 0
		}
		windowEnd = centerIndex + windowAfter
		if windowEnd >= m.totalSegments {
			windowEnd = m.totalSegments - 1
		}
	}

	evicted := 0
	m.segments.Range(func(key, value interface{}) bool {
		seg := value.(*SegmentCache)
		idx := seg.index

		// 窗口外的分片淘汰内存缓存
		if idx < windowStart || idx > windowEnd {
			seg.mu.Lock()
			if seg.data != nil {
				seg.data = nil
				m.memUsed.Add(-1)
				evicted++
			}
			seg.mu.Unlock()
		}
		return true
	})

	if evicted > 0 {
		slog.Debug("sliding window evicted memory cache",
			"center", centerIndex,
			"window", fmt.Sprintf("[%d,%d]", windowStart, windowEnd),
			"evicted", evicted,
			"mem_used", m.memUsed.Load())
	}
}

// TotalSegments 返回总分片数
func (m *SegmentCacheManager) TotalSegments() int {
	return m.totalSegments
}
