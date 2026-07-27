package response

// LoginResp 登录响应
type LoginResp struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

// RefreshResp 刷新 Token 响应（同 LoginResp）
type RefreshResp = LoginResp
