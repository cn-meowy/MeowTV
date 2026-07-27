package entity

// Role 用户角色枚举
type Role int8

const (
	RoleUser  Role = iota // 0 - 普通用户
	RoleAdmin             // 1 - 管理员
)

func (r Role) String() string {
	switch r {
	case RoleUser:
		return "user"
	case RoleAdmin:
		return "admin"
	default:
		return "unknown"
	}
}

func (r Role) IsValid() bool {
	return r == RoleUser || r == RoleAdmin
}

// Status 用户状态枚举
type Status int8

const (
	StatusDisabled Status = iota // 0 - 禁用
	StatusEnabled                // 1 - 启用
)

func (s Status) String() string {
	switch s {
	case StatusDisabled:
		return "disabled"
	case StatusEnabled:
		return "enabled"
	default:
		return "unknown"
	}
}

func (s Status) IsValid() bool {
	return s == StatusDisabled || s == StatusEnabled
}

// DeviceType 设备类型枚举
type DeviceType int8

const (
	DeviceWeb     DeviceType = iota // 0 - Web 浏览器
	DeviceAndroid                   // 1 - Android
	DeviceIOS                       // 2 - iOS
	DeviceAppleTV                   // 3 - Apple TV
)

func (d DeviceType) String() string {
	switch d {
	case DeviceWeb:
		return "web"
	case DeviceAndroid:
		return "android"
	case DeviceIOS:
		return "ios"
	case DeviceAppleTV:
		return "appletv"
	default:
		return "unknown"
	}
}

func (d DeviceType) IsValid() bool {
	return d >= DeviceWeb && d <= DeviceAppleTV
}
