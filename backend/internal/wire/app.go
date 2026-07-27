package wire

import (
	"cn.meow/meowtv/internal/auth"
	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/config"
	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/router"
	"cn.meow/meowtv/internal/service"
)

// App 是 wire injector 返回的聚合根，包含 main.go 需要访问的组件
type App struct {
	Config               *config.Config
	CacheProvider        *cache.CacheProvider
	JWTManager           *auth.JWTManager
	BlacklistManager     *auth.BlacklistManager
	AuthMiddleware       *middleware.NewAuthMiddleware
	SysConfigService     *service.SysConfigService
	ResourceService      *service.ResourceService
	DoubanImageService   *service.DoubanImageService
	DoubanRankService    *service.DoubanRankService
	ResourceImageService *service.ResourceImageService
	DownloadService      *service.DownloadService
	StreamService        *service.StreamService
	Handlers             *router.Handlers
}
