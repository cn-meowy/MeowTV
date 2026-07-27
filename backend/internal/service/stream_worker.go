package service

import (
	"container/heap"
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

const (
	// StreamChunkSize 流式推送 chunk 大小 (32KB)
	StreamChunkSize = 32 * 1024
	// StreamTimeout 分片下载超时
	StreamTimeout = 60 * time.Second
)

// Worker 工作协程
type Worker struct {
	id            int        // 协程 ID
	workerType    WorkerType // 协程类型
	assignedUser  int64      // 分配的用户 ID（专属协程用）
	session       *StreamSession
	generalQueue  *PriorityQueue // 通用任务队列（通用协程用，heap 结构）
	dedicatedTask chan *Task     // 任务队列（专属协程独占，channel 结构）
	taskNotify    chan struct{}  // 通用 worker 任务通知 channel
	stopCh        chan struct{}
	stopped       atomic.Bool
	wg            sync.WaitGroup
	mu            sync.Mutex
	currentTask   *Task
	cancelCh      chan struct{}      // 取消当前任务信号（缓冲 1，非阻塞发送）
	taskCtx       context.Context    // 当前任务 context（可取消）
	taskCancel    context.CancelFunc // 取消当前任务的 cancel 函数
}

// NewWorker 创建工作协程
// id: 协程 ID
// workerType: 协程类型
// userID: 分配的用户 ID（专属协程用）
// session: StreamSession
// generalQueue: 通用任务队列（通用协程用，为 nil 则使用 dedicatedTask）
// dedicatedTask: 专属任务 channel（专属协程用，传 nil 时自动创建）
// taskNotify: 通用 worker 任务通知 channel（通用协程用）
func NewWorker(id int, workerType WorkerType, userID int64, session *StreamSession, generalQueue *PriorityQueue, dedicatedTask chan *Task, taskNotify chan struct{}) *Worker {
	// 专属协程的 dedicatedTask 统一在此初始化，缓冲 20 支持批量分配
	if workerType == WorkerDedicated && dedicatedTask == nil {
		dedicatedTask = make(chan *Task, 20)
	}
	return &Worker{
		id:            id,
		workerType:    workerType,
		assignedUser:  userID,
		session:       session,
		generalQueue:  generalQueue,
		dedicatedTask: dedicatedTask,
		taskNotify:    taskNotify,
		stopCh:        make(chan struct{}),
		cancelCh:      make(chan struct{}, 1), // 缓冲 1，非阻塞发送
	}
}

// Run 启动工作协程
func (w *Worker) Run() {
	slog.Debug("worker started",
		"id", w.id,
		"type", w.workerType,
		"user_id", w.assignedUser,
		"session_key", w.session.GetSessionKey())

	if w.workerType == WorkerDedicated {
		w.runDedicated()
	} else {
		w.runGeneral()
	}

	slog.Debug("worker stopped",
		"id", w.id,
		"session_key", w.session.GetSessionKey())
}

// runDedicated 专属协程主循环
// 监听 cancelCh 以支持 seek 后任务取消：收到取消信号后跳过当前任务，继续等待新任务
func (w *Worker) runDedicated() {
	for {
		select {
		case <-w.stopCh:
			return
		case <-w.cancelCh:
			// 当前任务被取消（由 CancelCurrentTask 触发），继续等待新任务
			// taskCtx 已被 cancel，executeTask 中的 HTTP 请求会中断返回
			continue
		case task := <-w.dedicatedTask:
			if task != nil {
				w.executeTask(task)
			}
		}
	}
}

// runGeneral 通用协程主循环
// 等待任务通知或兜底轮询获取优先级最高的任务
func (w *Worker) runGeneral() {
	// 兜底轮询间隔，防止极端情况下通知丢失导致任务积压
	fallbackTicker := time.NewTicker(2 * time.Second)
	defer fallbackTicker.Stop()

	for {
		select {
		case <-w.stopCh:
			return
		case <-w.taskNotify:
			// 收到任务通知，立即尝试获取任务
			// 可能多个 worker 同时收到通知，只有一个能取到任务，其余自然落回等待
			task := w.popTask()
			if task != nil {
				w.executeTask(task)
			}
		case <-fallbackTicker.C:
			// 兜底：定期检查队列，防止通知丢失
			task := w.popTask()
			if task != nil {
				w.executeTask(task)
			}
		}
	}
}

// popTask 从通用队列弹出优先级最高的任务
// 线程安全：使用 PriorityQueue 内部 mutex 保护 heap.Pop
func (w *Worker) popTask() *Task {
	if w.generalQueue == nil {
		return nil
	}

	w.generalQueue.mu.Lock()
	defer w.generalQueue.mu.Unlock()

	if w.generalQueue.Len() == 0 {
		return nil
	}

	return heap.Pop(w.generalQueue).(*Task)
}

// executeTask 执行下载任务
// 统一下载原始TS数据（不后端解密），缓存到磁盘/内存
// 播放器通过代理获取原始数据后自行解密
// 使用可取消的 taskCtx，支持 seek 后中断无关任务
func (w *Worker) executeTask(task *Task) {
	w.mu.Lock()
	w.currentTask = task
	// 创建可取消的任务 context，使下载可被 CancelCurrentTask 中断
	taskCtx, taskCancel := context.WithTimeout(context.Background(), StreamTimeout)
	w.taskCtx = taskCtx
	w.taskCancel = taskCancel
	w.mu.Unlock()

	// 清理当前任务的 context 引用
	defer func() {
		w.mu.Lock()
		w.taskCancel = nil
		w.taskCtx = nil
		w.currentTask = nil
		w.mu.Unlock()
		// 确保资源释放（taskCancel 幂等，多次调用安全）
		taskCancel()
	}()

	segmentIndex := task.SegmentIndex
	cacheManager := w.session.GetCacheManager()

	// 检查分片状态
	status := cacheManager.GetStatus(segmentIndex)
	if status == SegmentStatusDone {
		slog.Debug("segment already done, skipping",
			"worker_id", w.id,
			"segment", segmentIndex)
		return
	}

	// 检查任务是否已被取消（seek 后可能立即取消）
	select {
	case <-taskCtx.Done():
		slog.Debug("task cancelled before download",
			"worker_id", w.id,
			"segment", segmentIndex)
		return
	default:
	}

	// 标记为下载中
	cacheManager.SetStatus(segmentIndex, SegmentStatusDownloading)

	slog.Info("worker starting download",
		"worker_id", w.id,
		"worker_type", w.workerType,
		"segment", segmentIndex,
		"urgent", task.Urgent)

	// 获取分片 URL
	m3u8Info := w.session.GetM3U8Info()
	if segmentIndex >= len(m3u8Info.Segments) {
		slog.Error("segment index out of range",
			"worker_id", w.id,
			"segment", segmentIndex,
			"total", len(m3u8Info.Segments))
		cacheManager.MarkSegmentFailed(segmentIndex)
		return
	}

	segInfo := m3u8Info.Segments[segmentIndex]

	// 创建 HTTP 客户端
	httpClient := &http.Client{
		Timeout: StreamTimeout,
	}

	// 统一下载原始TS数据（不后端解密，播放器自行解密）
	// 使用 taskCtx，CancelCurrentTask 可中断正在进行的 HTTP 请求
	w.downloadSegment(taskCtx, httpClient, segmentIndex, segInfo.URL)
}

// downloadSegment 统一下载分片原始数据（不后端解密，含重试机制）
// 播放器通过代理获取原始数据后自行解密，后端只负责缓存
func (w *Worker) downloadSegment(ctx context.Context, httpClient *http.Client, segmentIndex int, segURL string) {
	cacheManager := w.session.GetCacheManager()

	var lastErr error
	for attempt := 1; attempt <= MaxSegmentRetries; attempt++ {
		// 每次重试前检查状态，可能已被其他协程完成
		if cacheManager.GetStatus(segmentIndex) == SegmentStatusDone {
			return
		}

		// 重试时需要重新标记为 Downloading
		if attempt > 1 {
			cacheManager.SetStatus(segmentIndex, SegmentStatusDownloading)
		}

		data, err := w.doDownloadSegment(ctx, httpClient, segmentIndex, segURL)
		if err == nil {
			// 下载完成，标记完成并写入磁盘
			if markErr := cacheManager.MarkSegmentDone(segmentIndex, data); markErr != nil {
				slog.Error("mark segment done failed",
					"worker_id", w.id,
					"segment", segmentIndex,
					"error", markErr)
				return
			}

			slog.Info("segment downloaded",
				"worker_id", w.id,
				"segment", segmentIndex,
				"bytes", len(data))
			return
		}

		lastErr = err

		// 检查是否可重试
		if !IsRetryableError(err) {
			slog.Error("segment download failed (non-retryable)",
				"worker_id", w.id,
				"segment", segmentIndex,
				"attempt", attempt,
				"error", err)
			break
		}

		slog.Warn("segment download failed, retrying",
			"worker_id", w.id,
			"segment", segmentIndex,
			"attempt", attempt,
			"max_retries", MaxSegmentRetries,
			"error", err)
	}

	// 所有重试都失败
	slog.Error("segment download exhausted retries",
		"worker_id", w.id,
		"segment", segmentIndex,
		"max_retries", MaxSegmentRetries,
		"last_error", lastErr)
	cacheManager.MarkSegmentFailed(segmentIndex)
}

// doDownloadSegment 执行单次分片下载（下载原始数据，不解密）
func (w *Worker) doDownloadSegment(ctx context.Context, httpClient *http.Client, segmentIndex int, segURL string) ([]byte, error) {
	// 创建带超时的子 context
	dlCtx, cancel := context.WithTimeout(ctx, StreamTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(dlCtx, http.MethodGet, segURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", resp.StatusCode)
	}

	// 读取完整响应数据
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}

	slog.Debug("segment downloaded",
		"segment", segmentIndex,
		"bytes", len(data),
		"url", segURL)

	return data, nil
}

// Stop 停止工作协程
func (w *Worker) Stop() {
	if w.stopped.Load() {
		return
	}
	w.stopped.Store(true)
	close(w.stopCh)
}

// GetID 获取协程 ID
func (w *Worker) GetID() int {
	return w.id
}

// GetType 获取协程类型
func (w *Worker) GetType() WorkerType {
	return w.workerType
}

// GetAssignedUser 获取分配的用户 ID
func (w *Worker) GetAssignedUser() int64 {
	return w.assignedUser
}

// AssignTask 分配任务（专属协程），非阻塞
// channel 满时丢弃最旧任务，确保不阻塞调度器
func (w *Worker) AssignTask(task *Task) {
	select {
	case w.dedicatedTask <- task:
		// 成功入队
	default:
		// channel 满了，丢弃最旧任务后重试
		select {
		case <-w.dedicatedTask:
			// 取出旧任务丢弃
		default:
			// 极端情况：旧任务已被消费，无需丢弃
		}
		select {
		case w.dedicatedTask <- task:
			// 重试成功
		default:
			// 重试仍失败（极端竞态），记录日志
			slog.Warn("assign task dropped, dedicated channel full",
				"worker_id", w.id,
				"segment", task.SegmentIndex)
		}
	}
}

// GetCurrentTask 获取当前任务
func (w *Worker) GetCurrentTask() *Task {
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.currentTask
}

// CancelCurrentTask 取消当前正在执行的任务
// 通过取消 taskCtx 中断正在进行的 HTTP 请求，并发送 cancelCh 信号让 runDedicated 跳出等待
// 用于 seek 后中断专属 Worker 正在下载的无关分片
func (w *Worker) CancelCurrentTask() {
	w.mu.Lock()
	if w.taskCancel != nil {
		w.taskCancel()
		w.taskCancel = nil
	}
	w.mu.Unlock()
	// 非阻塞发送取消信号，runDedicated 收到后 continue 跳回循环顶部
	select {
	case w.cancelCh <- struct{}{}:
	default:
		// cancelCh 已有信号（缓冲 1），无需重复发送
	}
}

// ClearTaskQueue 清空专属任务队列中所有待执行任务
// 用于 seek 后清除专属 Worker 中尚未开始执行的旧任务，避免继续下载用户不再需要的位置
func (w *Worker) ClearTaskQueue() {
	if w.dedicatedTask == nil {
		return
	}
	cleared := 0
	for {
		select {
		case <-w.dedicatedTask:
			cleared++
		default:
			if cleared > 0 {
				slog.Debug("cleared dedicated task queue",
					"worker_id", w.id,
					"cleared", cleared)
			}
			return
		}
	}
}
