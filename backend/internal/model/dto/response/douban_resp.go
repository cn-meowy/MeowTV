package response

// TempTokenResp 通用临时 Token 响应
type TempTokenResp struct {
	Token     string `json:"token"`
	ExpiresIn int    `json:"expires_in"` // 秒
}
