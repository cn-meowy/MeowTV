package response

// QRCodeRequestResp 请求登录码响应
type QRCodeRequestResp struct {
	Code      string `json:"code"`
	QRURL     string `json:"qr_url"`
	ExpiresIn int64  `json:"expires_in"`
}

// QRCodePollResp 轮询登录结果响应
type QRCodePollResp struct {
	Status       string `json:"status"` // waiting / confirmed / expired
	AccessToken  string `json:"access_token,omitempty"`
	RefreshToken string `json:"refresh_token,omitempty"`
	ExpiresIn    int64  `json:"expires_in,omitempty"`
}
