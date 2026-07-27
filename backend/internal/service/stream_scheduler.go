package service

import (
	"container/heap"
	"context"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"time"
)

type WorkerType int

const (
	WorkerDedicated WorkerType = 0
	WorkerGeneral   WorkerType = 1
)

func (wt WorkerType) String() string {
	switch wt {
	case WorkerDedicated:
		return "dedicated"
	case WorkerGeneral:
		return "general"
	default:
		return "unknown"
	}
}

type Task struct {
	SegmentIndex int
	Priority     int
	Urgent       bool
	UserID       int64
}

type PriorityQueue struct {
	items []*Task
	mu    sync.Mutex
}

func (pq *PriorityQueue) Len() int { return len(pq.items) }
func (pq *PriorityQueue) Less(i, j int) bool {
	return pq.items[i].Priority < pq.items[j].Priority
}
func (pq *PriorityQueue) Swap(i, j int) {
	pq.items[i], pq.items[j] = pq.items[j], pq.items[i]
}
func (pq *PriorityQueue) Push(x interface{}) { pq.items = append(pq.items, x.(*Task)) }
func (pq *PriorityQueue) Pop() interface{} {
	n := len(pq.items)
	item := pq.items[n-1]
	pq.items[n-1] = nil
	pq.items = pq.items[:n-1]
	return item
}
func (pq *PriorityQueue) Peek() *Task {
	if len(pq.items) == 0 {
		return nil
	}
	return pq.items[0]
}
func (pq *PriorityQueue) Clear() { pq.items = nil }

type SegmentNeed struct {
	index  int
	urgent bool
	userID int64
}

type StreamConfig struct {
	BufferSize     int
	GeneralWorkers int
	MaxWorkers     int
	AutoSave       bool
	IsEnable       bool
	MaxDiskCacheMB int // 磁盘缓存上限（MB），0 表示不限制，默认 10240（10GB）
}

func DefaultStreamConfig() *StreamConfig {
	return &StreamConfig{BufferSize: 20, GeneralWorkers: 5, MaxWorkers: 8, MaxDiskCacheMB: 10240}
}

type ScheduleCenter struct {
	session        *StreamSession
	generalQueue   *PriorityQueue
	workers        map[int]*Worker
	workerCount    atomic.Int32
	maxWorkers     int
	generalCount   int
	config         *StreamConfig
	ctx            context.Context
	cancel         context.CancelFunc
	wg             sync.WaitGroup
	runMu          sync.Mutex
	running        bool
	stopped        chan struct{}
	muWorker       sync.Mutex
	seekNotify     chan struct{}
	taskNotify     chan struct{} // 通知通用 worker 有新任务入队
	lastSeekTarget atomic.Int32
}

func NewScheduleCenter(session *StreamSession, config *StreamConfig) *ScheduleCenter {
	if config == nil {
		config = DefaultStreamConfig()
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &ScheduleCenter{
		session:      session,
		generalQueue: &PriorityQueue{items: make([]*Task, 0)},
		workers:      make(map[int]*Worker),
		maxWorkers:   config.MaxWorkers,
		generalCount: config.GeneralWorkers,
		config:       config,
		ctx:          ctx,
		cancel:       cancel,
		stopped:      make(chan struct{}),
		seekNotify:   make(chan struct{}, 1),
		taskNotify:   make(chan struct{}, 1),
	}
}

func (sc *ScheduleCenter) Start() {
	sc.runMu.Lock()
	defer sc.runMu.Unlock()
	if sc.running {
		return
	}
	sc.running = true
	slog.Info("schedule center starting", "session_key", sc.session.GetSessionKey(), "max_workers", sc.maxWorkers, "general_workers", sc.generalCount)
	for i := 0; i < sc.generalCount; i++ {
		sc.spawnGeneralWorker(i)
	}
	sc.wg.Add(1)
	go sc.runLoop()
}

func (sc *ScheduleCenter) Stop() {
	sc.runMu.Lock()
	if !sc.running {
		sc.runMu.Unlock()
		return
	}
	sc.running = false
	sc.runMu.Unlock()
	slog.Info("schedule center stopping", "session_key", sc.session.GetSessionKey())

	// 1. 先取消 context，让 runLoop 和下载中的任务感知退出信号
	sc.cancel()

	// 2. 停止所有 worker（关闭 stopCh），让 worker 主循环退出
	//    必须在 wg.Wait() 之前，否则 worker 永远不会退出导致死锁
	sc.muWorker.Lock()
	for _, w := range sc.workers {
		w.Stop()
	}
	sc.workers = make(map[int]*Worker)
	sc.muWorker.Unlock()

	// 3. 等待所有 goroutine（runLoop + workers）退出
	sc.wg.Wait()

	close(sc.stopped)
	slog.Info("schedule center stopped", "session_key", sc.session.GetSessionKey())
}

func (sc *ScheduleCenter) runLoop() {
	defer sc.wg.Done()
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-sc.ctx.Done():
			return
		case <-sc.seekNotify:
			sc.schedule()
		case <-ticker.C:
			sc.schedule()
		}
	}
}

// NotifySeek 通知调度器发生了 seek，立即触发调度重算
func (sc *ScheduleCenter) NotifySeek(targetIndex int) {
	sc.lastSeekTarget.Store(int32(targetIndex))
	select {
	case sc.seekNotify <- struct{}{}:
	default:
	}
}

// NotifyUrgentSegment 通知调度器某个分片需要优先下载
func (sc *ScheduleCenter) NotifyUrgentSegment(segmentIndex int) {
	sc.generalQueue.mu.Lock()
	for i, item := range sc.generalQueue.items {
		if item.SegmentIndex == segmentIndex {
			sc.generalQueue.items[i].Priority = 0
			heap.Fix(sc.generalQueue, i)
			sc.generalQueue.mu.Unlock()
			select {
			case sc.seekNotify <- struct{}{}:
			default:
			}
			return
		}
	}
	cm := sc.session.GetCacheManager()
	status := cm.GetStatus(segmentIndex)
	if status == SegmentStatusPending || status == SegmentStatusFailed {
		heap.Push(sc.generalQueue, &Task{SegmentIndex: segmentIndex, Priority: 0})
	}
	sc.generalQueue.mu.Unlock()
	select {
	case sc.seekNotify <- struct{}{}:
	default:
	}
}

func (sc *ScheduleCenter) schedule() {
	session := sc.session
	cm := session.GetCacheManager()
	users := session.GetAllUsers()
	if len(users) == 0 {
		return
	}
	bufSz := sc.config.BufferSize

	seekTarget := int(sc.lastSeekTarget.Swap(-1))
	if seekTarget >= 0 {
		sc.handleSeek(seekTarget, cm, bufSz)
	}

	// 确保每个活跃用户有守护 Worker（持续跟随用户进度下载未完成分片）
	sc.ensureGuardianWorkers(users)

	// 根据用户最新进度更新守护 Worker 任务，确保始终在用户播放位置附近下载
	sc.rebalanceGuardianTasks(users, cm, bufSz)

	// 收集所有用户当前位置前方需要下载的分片，分配给专属 Worker（兜底）
	needs := make([]SegmentNeed, 0)
	assigned := make(map[int]bool)
	for _, user := range users {
		cur := user.CurrentIndex
		end := cur + bufSz
		if end > cm.TotalSegments() {
			end = cm.TotalSegments()
		}
		for i := cur; i < end; i++ {
			st := cm.GetStatus(i)
			if st == SegmentStatusPending || st == SegmentStatusFailed {
				if !assigned[i] {
					needs = append(needs, SegmentNeed{index: i, urgent: true, userID: user.UserID})
					assigned[i] = true
				}
			}
		}
	}
	sc.assignUrgentTasks(needs, users)
	sc.fillGeneralQueue(assigned, cm)
}

// handleSeek 处理 seek：清空通用队列，以 seek 位置为中心重新填充
// 同时中断所有专属 Worker 的无关任务，重新分配 seek 位置附近的任务
func (sc *ScheduleCenter) handleSeek(seekTarget int, cm *SegmentCacheManager, bufSz int) {
	slog.Info("handling seek", "session_key", sc.session.GetSessionKey(), "seek_target", seekTarget)

	// 1. 清空通用队列
	sc.generalQueue.mu.Lock()
	sc.generalQueue.Clear()
	sc.generalQueue.mu.Unlock()

	// 2. 以 seekTarget 为中心重填通用队列
	seekEnd := seekTarget + bufSz*2
	if seekEnd > cm.TotalSegments() {
		seekEnd = cm.TotalSegments()
	}
	priority := 0
	sc.generalQueue.mu.Lock()
	for i := seekTarget; i < seekEnd; i++ {
		st := cm.GetStatus(i)
		if st == SegmentStatusPending || st == SegmentStatusFailed {
			heap.Push(sc.generalQueue, &Task{SegmentIndex: i, Priority: priority})
			priority++
		}
	}
	sc.generalQueue.mu.Unlock()

	// 3. 中断所有专属 Worker 的无关任务并清空任务队列
	// seek 后用户不再需要旧位置的分片，立即取消避免浪费带宽
	seekRangeEnd := seekTarget + bufSz
	if seekRangeEnd > cm.TotalSegments() {
		seekRangeEnd = cm.TotalSegments()
	}
	sc.muWorker.Lock()
	var dedicatedWorkers []*Worker
	for _, w := range sc.workers {
		if w.GetType() == WorkerDedicated {
			dedicatedWorkers = append(dedicatedWorkers, w)
		}
	}
	sc.muWorker.Unlock()

	for _, w := range dedicatedWorkers {
		// 取消当前正在执行的任务（中断 HTTP 请求）
		w.CancelCurrentTask()
		// 清空待执行的任务队列
		w.ClearTaskQueue()

		// 重置被取消的 Downloading 分片状态为 Pending
		// 避免 Worker 取消后分片卡在 Downloading 状态导致无人继续下载
		if curTask := w.GetCurrentTask(); curTask != nil {
			idx := curTask.SegmentIndex
			// 如果取消的分片不在 seek 范围内，重置为 Pending
			if idx < seekTarget || idx >= seekRangeEnd {
				cm.ResetDownloadingToPending(idx)
			}
		}
	}

	// 4. 为每个活跃用户的专属 Worker 重新分配 seek 位置附近的任务
	users := sc.session.GetAllUsers()
	assigned := make(map[int]bool)
	for _, user := range users {
		// 查找该用户对应的专属 Worker
		var dw *Worker
		sc.muWorker.Lock()
		for _, w := range sc.workers {
			if w.GetType() == WorkerDedicated && w.GetAssignedUser() == user.UserID {
				dw = w
				break
			}
		}
		sc.muWorker.Unlock()
		if dw == nil {
			continue
		}

		// 分配 seek 位置到 seekRangeEnd 范围内的 Pending 分片
		batchSize := 0
		for i := seekTarget; i < seekRangeEnd && batchSize < bufSz; i++ {
			if assigned[i] {
				continue
			}
			st := cm.GetStatus(i)
			if st == SegmentStatusPending || st == SegmentStatusFailed {
				dw.AssignTask(&Task{
					SegmentIndex: i,
					Priority:     i - seekTarget,
					Urgent:       true,
					UserID:       user.UserID,
				})
				assigned[i] = true
				batchSize++
			}
		}
	}

	slog.Info("seek handled, dedicated workers reassigned",
		"session_key", sc.session.GetSessionKey(),
		"seek_target", seekTarget,
		"seek_range_end", seekRangeEnd,
		"reassigned_workers", len(dedicatedWorkers))
}

// assignUrgentTasks 批量分配紧急任务给专属协程
func (sc *ScheduleCenter) assignUrgentTasks(needs []SegmentNeed, users []*UserProgress) {
	userTasks := make(map[int64][]*Task)
	for _, need := range needs {
		if need.urgent {
			userTasks[need.userID] = append(userTasks[need.userID], &Task{
				SegmentIndex: need.index,
				Priority:     need.index,
				Urgent:       true,
				UserID:       need.userID,
			})
		}
	}
	for _, user := range users {
		tasks, ok := userTasks[user.UserID]
		if !ok || len(tasks) == 0 {
			continue
		}
		var dw *Worker
		sc.muWorker.Lock()
		for _, w := range sc.workers {
			if w.GetType() == WorkerDedicated && w.GetAssignedUser() == user.UserID {
				dw = w
				break
			}
		}
		sc.muWorker.Unlock()
		if dw == nil {
			dw = sc.spawnDedicatedWorker(user.UserID)
		}
		if dw != nil {
			// 批量分配：一次分配多个紧急任务，加快 seek 后的缓冲速度
			batchSize := len(tasks)
			if batchSize > sc.config.BufferSize {
				batchSize = sc.config.BufferSize
			}
			for i := 0; i < batchSize; i++ {
				dw.AssignTask(tasks[i])
			}
		}
	}
}

// fillGeneralQueue 填充通用任务队列（增量模式）
func (sc *ScheduleCenter) fillGeneralQueue(assigned map[int]bool, cm *SegmentCacheManager) {
	sc.generalQueue.mu.Lock()
	queuedSet := make(map[int]bool)
	for _, item := range sc.generalQueue.items {
		queuedSet[item.SegmentIndex] = true
	}
	priority := len(sc.generalQueue.items)
	added := 0
	for i := 0; i < cm.TotalSegments(); i++ {
		if assigned[i] || queuedSet[i] {
			continue
		}
		st := cm.GetStatus(i)
		if st == SegmentStatusPending || st == SegmentStatusFailed {
			heap.Push(sc.generalQueue, &Task{SegmentIndex: i, Priority: priority})
			priority++
			added++
		}
	}
	sc.generalQueue.mu.Unlock()

	// 有新任务入队时通知通用 worker（非阻塞发送，channel 缓冲为 1）
	if added > 0 {
		select {
		case sc.taskNotify <- struct{}{}:
		default:
		}
	}
}

func (sc *ScheduleCenter) spawnGeneralWorker(id int) {
	worker := NewWorker(id, WorkerGeneral, 0, sc.session, sc.generalQueue, nil, sc.taskNotify)
	sc.muWorker.Lock()
	sc.workers[worker.GetID()] = worker
	wc := len(sc.workers)
	sc.muWorker.Unlock()
	sc.workerCount.Add(1)
	sc.wg.Add(1)
	go func() {
		defer sc.wg.Done()
		worker.Run()
	}()
	slog.Debug("spawned general worker", "id", id, "worker_count", wc, "session_key", sc.session.GetSessionKey())
}

func (sc *ScheduleCenter) spawnDedicatedWorker(userID int64) *Worker {
	maxAllowed := sc.maxWorkers
	if maxAllowed < 8 {
		maxAllowed = 8
	}
	activeUsers := sc.session.GetUserCount()
	// 守护协程机制：确保每个活跃用户至少有 1 个专属 Worker，加上 5 个通用 Worker 余量
	if maxAllowed < activeUsers+5 {
		maxAllowed = activeUsers + 5
	}
	workerCount := int(sc.workerCount.Load())
	if workerCount >= maxAllowed {
		slog.Debug("cannot spawn dedicated worker, max workers reached", "user_id", userID, "worker_count", workerCount, "max_allowed", maxAllowed)
		return nil
	}
	// 移除通用 Worker >= 4 的限制，确保每个活跃用户始终有守护 Worker
	worker := NewWorker(int(sc.workerCount.Load()), WorkerDedicated, userID, sc.session, nil, nil, nil)
	sc.muWorker.Lock()
	sc.workers[worker.GetID()] = worker
	workerCount = len(sc.workers)
	sc.muWorker.Unlock()
	sc.workerCount.Add(1)
	sc.wg.Add(1)
	go func() {
		defer sc.wg.Done()
		worker.Run()
	}()
	slog.Info("spawned dedicated worker", "id", worker.GetID(), "user_id", userID, "worker_count", workerCount, "session_key", sc.session.GetSessionKey())
	return worker
}

// ensureGuardianWorkers 确保每个活跃用户有守护 Worker
// 守护 Worker 是专属 Worker，持续跟随用户播放进度下载未完成分片
// 如果用户数超过 maxWorkers 上限，回收最久未活跃用户的 Worker 重新分配
func (sc *ScheduleCenter) ensureGuardianWorkers(users []*UserProgress) {
	// 收集当前所有专属 Worker 的 assignedUser 集合
	sc.muWorker.Lock()
	dedicatedByUser := make(map[int64]*Worker)
	for _, w := range sc.workers {
		if w.GetType() == WorkerDedicated {
			dedicatedByUser[w.GetAssignedUser()] = w
		}
	}
	sc.muWorker.Unlock()

	// 检查活跃用户集合
	activeUserIDs := make(map[int64]bool, len(users))
	for _, user := range users {
		activeUserIDs[user.UserID] = true
	}

	// 回收已离开用户的专属 Worker
	for assignedUser, w := range dedicatedByUser {
		if !activeUserIDs[assignedUser] {
			slog.Info("recycling orphaned dedicated worker (user left)",
				"worker_id", w.GetID(),
				"user_id", assignedUser,
				"session_key", sc.session.GetSessionKey())
			w.CancelCurrentTask()
			w.ClearTaskQueue()
			w.Stop()
			sc.muWorker.Lock()
			delete(sc.workers, w.GetID())
			sc.muWorker.Unlock()
			sc.workerCount.Add(-1)
			delete(dedicatedByUser, assignedUser)
		}
	}

	// 为没有专属 Worker 的活跃用户创建守护 Worker
	for _, user := range users {
		if _, exists := dedicatedByUser[user.UserID]; exists {
			continue
		}
		// 尝试创建新的守护 Worker
		dw := sc.spawnDedicatedWorker(user.UserID)
		if dw != nil {
			dedicatedByUser[user.UserID] = dw
			slog.Info("guardian worker ensured",
				"user_id", user.UserID,
				"worker_id", dw.GetID(),
				"session_key", sc.session.GetSessionKey())
			continue
		}
		// 创建失败（达到上限），尝试回收最久未活跃的专属 Worker 重新分配
		recycled := sc.recycleOldestDedicatedWorker(user.UserID, dedicatedByUser)
		if !recycled {
			slog.Warn("cannot ensure guardian worker, worker limit reached",
				"user_id", user.UserID,
				"session_key", sc.session.GetSessionKey())
		}
	}
}

// recycleOldestDedicatedWorker 回收最久未活跃的专属 Worker，重新分配给新用户
// 返回 true 表示成功回收并重新分配
func (sc *ScheduleCenter) recycleOldestDedicatedWorker(newUserID int64, dedicatedByUser map[int64]*Worker) bool {
	var oldestWorker *Worker
	var oldestUserID int64
	oldestReport := time.Now()

	sc.muWorker.Lock()
	for _, w := range sc.workers {
		if w.GetType() != WorkerDedicated {
			continue
		}
		// 获取该 Worker 对应用户的最后上报时间
		if up, ok := sc.session.GetUser(w.GetAssignedUser()); ok {
			if up.LastReport.Before(oldestReport) {
				oldestReport = up.LastReport
				oldestWorker = w
				oldestUserID = w.GetAssignedUser()
			}
		}
	}
	sc.muWorker.Unlock()

	if oldestWorker == nil || oldestUserID == newUserID {
		return false
	}

	// 停止旧 Worker
	oldestWorker.CancelCurrentTask()
	oldestWorker.ClearTaskQueue()
	oldestWorker.Stop()
	sc.muWorker.Lock()
	delete(sc.workers, oldestWorker.GetID())
	sc.muWorker.Unlock()
	sc.workerCount.Add(-1)
	delete(dedicatedByUser, oldestUserID)

	// 为新用户创建 Worker
	dw := sc.spawnDedicatedWorker(newUserID)
	if dw != nil {
		dedicatedByUser[newUserID] = dw
		slog.Info("recycled oldest dedicated worker for new user",
			"old_user_id", oldestUserID,
			"new_user_id", newUserID,
			"worker_id", dw.GetID(),
			"session_key", sc.session.GetSessionKey())
		return true
	}
	return false
}

// rebalanceGuardianTasks 根据用户最新进度更新守护 Worker 任务
// 确保每个守护 Worker 始终在用户播放位置附近下载未完成分片
// 如果守护 Worker 的当前任务不在用户播放窗口内，取消并重新分配
func (sc *ScheduleCenter) rebalanceGuardianTasks(users []*UserProgress, cm *SegmentCacheManager, bufSz int) {
	for _, user := range users {
		sc.muWorker.Lock()
		var dw *Worker
		for _, w := range sc.workers {
			if w.GetType() == WorkerDedicated && w.GetAssignedUser() == user.UserID {
				dw = w
				break
			}
		}
		sc.muWorker.Unlock()
		if dw == nil {
			continue
		}

		// 计算用户播放窗口 [cur, cur+bufSz)
		cur := user.CurrentIndex
		windowEnd := cur + bufSz
		if windowEnd > cm.TotalSegments() {
			windowEnd = cm.TotalSegments()
		}

		// 检查当前任务是否在播放窗口内
		currentTask := dw.GetCurrentTask()
		if currentTask != nil {
			taskIdx := currentTask.SegmentIndex
			if taskIdx < cur || taskIdx >= windowEnd {
				// 当前任务不在播放窗口内，取消并重置状态
				dw.CancelCurrentTask()
				dw.ClearTaskQueue()
				cm.ResetDownloadingToPending(taskIdx)
				slog.Debug("guardian worker task out of window, rebalancing",
					"user_id", user.UserID,
					"task_segment", taskIdx,
					"window", fmt.Sprintf("[%d,%d)", cur, windowEnd))
			}
		}

		// 为守护 Worker 分配播放窗口内的 Pending 分片（增量补充）
		// 如果 Worker 当前空闲且有 Pending 分片，立即分配
		assigned := 0
		for i := cur; i < windowEnd && assigned < bufSz; i++ {
			st := cm.GetStatus(i)
			if st == SegmentStatusPending || st == SegmentStatusFailed {
				dw.AssignTask(&Task{
					SegmentIndex: i,
					Priority:     i - cur,
					Urgent:       true,
					UserID:       user.UserID,
				})
				assigned++
			}
		}
	}
}

func (sc *ScheduleCenter) GetGeneralQueue() *PriorityQueue { return sc.generalQueue }
func (sc *ScheduleCenter) GetWorkerCount() int             { return int(sc.workerCount.Load()) }
func (sc *ScheduleCenter) IsRunning() bool {
	sc.runMu.Lock()
	defer sc.runMu.Unlock()
	return sc.running
}
