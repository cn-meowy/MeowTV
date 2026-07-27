package request

// ConfigListReq 系统配置列表请求
type ConfigListReq struct {
	Group string `json:"group" validate:"omitempty,max=64"`
}

// ConfigCreateReq 创建系统配置请求
type ConfigCreateReq struct {
	ConfigKey   string `json:"config_key" validate:"required,max=128"`
	ConfigGroup string `json:"config_group" validate:"required,max=64"`
	Title       string `json:"title" validate:"omitempty,max=256"`
	Title1      string `json:"title1" validate:"omitempty,max=128"`
	Title2      string `json:"title2" validate:"omitempty,max=128"`
	Title3      string `json:"title3" validate:"omitempty,max=128"`
	Title4      string `json:"title4" validate:"omitempty,max=128"`
	Title5      string `json:"title5" validate:"omitempty,max=128"`
	Title6      string `json:"title6" validate:"omitempty,max=128"`
	Value1      string `json:"value1" validate:"omitempty,max=1024"`
	Value2      string `json:"value2" validate:"omitempty,max=1024"`
	Value3      string `json:"value3" validate:"omitempty,max=1024"`
	Value4      string `json:"value4" validate:"omitempty,max=1024"`
	Value5      string `json:"value5" validate:"omitempty,max=1024"`
	Value6      string `json:"value6" validate:"omitempty,max=1024"`
	SortOrder   int    `json:"sort_order" validate:"omitempty"`
	IsEnabled   bool   `json:"is_enabled"`
	Remark      string `json:"remark" validate:"omitempty,max=512"`
}

// ConfigUpdateReq 更新系统配置请求（按 config_key 更新）
type ConfigUpdateReq struct {
	ConfigKey string  `json:"config_key" validate:"required,max=128"`
	Title     *string `json:"title" validate:"omitempty,max=256"`
	Title1    *string `json:"title1" validate:"omitempty,max=128"`
	Title2    *string `json:"title2" validate:"omitempty,max=128"`
	Title3    *string `json:"title3" validate:"omitempty,max=128"`
	Title4    *string `json:"title4" validate:"omitempty,max=128"`
	Title5    *string `json:"title5" validate:"omitempty,max=128"`
	Title6    *string `json:"title6" validate:"omitempty,max=128"`
	Value1    *string `json:"value1" validate:"omitempty,max=1024"`
	Value2    *string `json:"value2" validate:"omitempty,max=1024"`
	Value3    *string `json:"value3" validate:"omitempty,max=1024"`
	Value4    *string `json:"value4" validate:"omitempty,max=1024"`
	Value5    *string `json:"value5" validate:"omitempty,max=1024"`
	Value6    *string `json:"value6" validate:"omitempty,max=1024"`
	SortOrder *int    `json:"sort_order" validate:"omitempty"`
	IsEnabled *bool   `json:"is_enabled"`
	Remark    *string `json:"remark" validate:"omitempty,max=512"`
}

// ConfigDeleteReq 删除系统配置请求
type ConfigDeleteReq struct {
	ID int64 `json:"id" validate:"required"`
}
