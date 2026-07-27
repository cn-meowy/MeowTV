package response

// StreamSessionResp 流会话信息响应
type StreamSessionResp struct {
	SessionKey      string  `json:"session_key"`
	TotalSegments   int     `json:"total_segments"`
	Duration        float64 `json:"duration"`
	DownloadedCount int     `json:"downloaded_count"`
}

// StreamSaveResp 保存为下载任务响应
type StreamSaveResp struct {
	TaskID int64 `json:"task_id"`
	Queued bool  `json:"queued"`
}

// StreamCloseResp 关闭会话响应
type StreamCloseResp struct {
	Closed bool `json:"closed"`
}

// M3u8CheckResultItem 单个 m3u8 链接检测结果
type M3u8CheckResultItem struct {
	URL        string `json:"url"`
	Available  bool   `json:"available"`
	StatusCode int    `json:"status_code"`
	Error      string `json:"error"`
}

// StreamCheckResp m3u8 链接检测响应
type StreamCheckResp struct {
	Results []M3u8CheckResultItem `json:"results"`
}
