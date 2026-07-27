package service

// SaveCallback 流会话完成后的保存回调接口
// 用于解耦 StreamService 与 DownloadService 的循环依赖
type SaveCallback interface {
	// SaveFromStream 从流缓存保存为下载任务
	// sessionKey: 会话标识
	// segmentDir: 分片临时目录（已包含所有 seg_XXXX.ts 文件）
	// totalSegments: 总分片数
	// userID: 触发用户 ID
	// vodInfo: 影视资源完整信息
	// m3u8Info: m3u8 解析结果（包含加密信息，合并时用于解密）
	// 返回: taskID, error
	SaveFromStream(sessionKey string, segmentDir string, totalSegments int,
		userID int64, vodInfo *VodInfo, m3u8Info *M3u8Info) (int64, error)
}
