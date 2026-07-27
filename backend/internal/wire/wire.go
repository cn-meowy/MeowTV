//go:build wireinject

package wire

import (
	"github.com/google/wire"

	"cn.meow/meowtv/internal/auth"
	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/config"
	"cn.meow/meowtv/internal/handler"
	"cn.meow/meowtv/internal/handler/middleware"
	"cn.meow/meowtv/internal/repository"
	"cn.meow/meowtv/internal/router"
	"cn.meow/meowtv/internal/service"

	"gorm.io/gorm"
)

// ConfigSet provides configuration sub-config extraction providers.
// *Config itself is provided as an injector argument (loaded in main.go before wire).
var ConfigSet = wire.NewSet(
	ProvideAuthConfig,
	ProvideDBConfig,
	ProvideCacheConfig,
	ProvideAppConfig,
)

// CacheSet provides cache-related dependencies.
var CacheSet = wire.NewSet(
	cache.NewCacheProvider,
	ProvideCache,
)

// DBSet is intentionally empty.
// *gorm.DB is created in main.go before wire injection (for migrations),
// so it is provided as an injector argument instead of a provider.
var DBSet = wire.NewSet()

// AuthSet provides auth-related dependencies.
var AuthSet = wire.NewSet(
	auth.NewJWTManager,
	auth.NewBlacklistManager,
	auth.NewQRCodeManager,
	middleware.NewAuthProviders,
)

// RepositorySet provides repository layer dependencies.
var RepositorySet = wire.NewSet(
	repository.NewUserRepository,
	repository.NewSysConfigRepository,
	repository.NewUserGroupRepository,
	repository.NewSearchHistoryRepository,
	repository.NewPlayHistoryRepository,
	repository.NewFavoriteRepository,
	repository.NewDownloadRepository,
	repository.NewDoubanRankRepository,
)

// ServiceSet provides service layer dependencies.
var ServiceSet = wire.NewSet(
	service.NewAuthService,
	service.NewUserService,
	service.NewSysConfigService,
	service.NewDoubanClient,
	service.NewDoubanService,
	service.NewDoubanImageService,
	service.NewDoubanRankService,
	service.NewResourceService,
	service.NewResourceImageService,
	service.NewSearchService,
	service.NewSearchHistoryService,
	service.NewPlayHistoryService,
	service.NewFavoriteService,
	service.NewDownloadService,
	service.NewUserGroupService,
	service.NewStreamService,
)

// HandlerSet provides handler layer dependencies.
var HandlerSet = wire.NewSet(
	handler.NewAuthHandler,
	handler.NewUserHandler,
	handler.NewAdminHandler,
	handler.NewAdminConfigHandler,
	handler.NewAdminGroupHandler,
	handler.NewDoubanHandler,
	handler.NewResourceHandler,
	handler.NewUserDataHandler,
	handler.NewDownloadHandler,
	handler.NewStreamHandler,
)

// SuperSet contains all provider sets.
var SuperSet = wire.NewSet(
	ConfigSet,
	CacheSet,
	DBSet,
	AuthSet,
	RepositorySet,
	ServiceSet,
	HandlerSet,
)

// InitializeApp 是 wire injector 入口。
// cfg 和 db 参数由 main.go 提前创建并传入（因为需要先做迁移和日志初始化）。
// wire 将根据 Provider Set 自动生成此函数的实现到 wire_gen.go。
func InitializeApp(cfg *config.Config, db *gorm.DB) (*App, error) {
	wire.Build(
		SuperSet,
		wire.Struct(new(router.Handlers), "*"),
		wire.Struct(new(App), "*"),
	)
	return nil, nil
}
