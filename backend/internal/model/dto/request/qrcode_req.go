package request

// QRCodeRequestReq TV 端请求登录码
type QRCodeRequestReq struct {
	DeviceID   string `json:"device_id" validate:"required"`
	DeviceName string `json:"device_name" validate:"required,min=1,max=200"`
	// DeviceType 使用指针，以便 validator 的 required 能区分"未传"(nil)与合法零值(Web=0)
	DeviceType *int8 `json:"device_type" validate:"required,min=0,max=3"`
}

// QRCodeScanReq 手机端扫码确认（纯授权，不传设备信息）
type QRCodeScanReq struct {
	Code string `json:"code" validate:"required,min=8,max=8"`
}

// QRCodePollReq TV 端轮询登录结果
type QRCodePollReq struct {
	Code       string `json:"code" validate:"required,min=8,max=8"`
	DeviceID   string `json:"device_id" validate:"required,min=1,max=128"`
	DeviceName string `json:"device_name" validate:"required,min=1,max=200"`
	DeviceType *int8  `json:"device_type" validate:"required,min=0,max=3"`
}
