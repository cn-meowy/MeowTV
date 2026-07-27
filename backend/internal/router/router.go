package router

import (
	"time"

	"github.com/go-playground/validator/v10"
	"github.com/labstack/echo/v4"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/handler"
	"cn.meow/meowtv/internal/handler/middleware"
)

// Config holds router configuration.
type Config struct {
	Debug bool
}

// Handlers holds all handler instances.
type Handlers struct {
	Auth        *handler.AuthHandler
	User        *handler.UserHandler
	Admin       *handler.AdminHandler
	AdminConfig *handler.AdminConfigHandler
	AdminGroup  *handler.AdminGroupHandler
	Douban      *handler.DoubanHandler
	Resource    *handler.ResourceHandler
	UserData    *handler.UserDataHandler
	Download    *handler.DownloadHandler
	Stream      *handler.StreamHandler
	TempToken   *handler.TempTokenHandler
}

// CustomValidator is a custom validator for Echo.
type CustomValidator struct {
	Validator *validator.Validate
}

// Validate implements the echo.Validator interface.
func (cv *CustomValidator) Validate(i interface{}) error {
	if err := cv.Validator.Struct(i); err != nil {
		return err
	}
	return nil
}

// New creates and configures the Echo instance with all routes and middleware.
func New(cfg Config, h *Handlers, authMid *middleware.NewAuthMiddleware, corsOrigins []string, cacheInstance cache.Cache) *echo.Echo {
	e := echo.New()
	e.HideBanner = true
	e.HidePort = true

	// Configure validator
	e.Validator = &CustomValidator{Validator: validator.New()}

	// Global middleware order: Recovery -> Logger -> CORS -> Auth (per-route)
	e.Use(middleware.Recovery())
	e.Use(middleware.Logger())
	e.Use(middleware.CORS(middleware.CORSConfig{AllowedOrigins: corsOrigins}))

	// Global error handler
	e.HTTPErrorHandler = middleware.ErrorHandler()

	// Health check endpoint (no auth required)
	e.GET("/health", healthHandler)

	// API routes (grouped)
	api := e.Group("/api")

	// Auth routes - public (no auth required)
	authPublic := api.Group("/auth")
	authPublic.POST("/login", h.Auth.Login)
	authPublic.POST("/refresh", h.Auth.Refresh)
	authPublic.POST("/logout", h.Auth.Logout)
	authPublic.POST("/qrcode/request", h.Auth.QRCodeRequest)
	authPublic.POST("/qrcode/poll", h.Auth.QRCodePoll)

	// Auth routes - protected (auth required for scan confirmation)
	authProtected := api.Group("/auth")
	authProtected.Use(authMid.Auth())
	authProtected.POST("/qrcode/scan", h.Auth.QRCodeScan)

	// User routes (auth required)
	user := api.Group("/user")
	user.Use(authMid.Auth())
	user.POST("/profile", h.User.Profile)
	user.POST("/update", h.User.UpdateProfile)
	user.POST("/password", h.User.ChangePassword)
	user.POST("/devices", h.User.Devices)
	user.POST("/kick-device", h.User.KickDevice)
	user.POST("/config/list", h.AdminConfig.List)

	// Admin routes (admin required)
	admin := api.Group("/admin")
	admin.Use(authMid.AuthAdmin())
	admin.POST("/user/create", h.Admin.CreateUser)
	admin.POST("/user/update", h.Admin.UpdateUser)
	admin.POST("/user/reset-password", h.Admin.ResetPassword)
	admin.POST("/user/list", h.Admin.UserList)
	admin.POST("/user/delete", h.Admin.DeleteUser)
	admin.POST("/user/kick", h.Admin.KickUser)

	// Admin config routes (admin required)
	admin.POST("/config/list", h.AdminConfig.List)
	admin.POST("/config/create", h.AdminConfig.Create)
	admin.POST("/config/update", h.AdminConfig.Update)
	admin.POST("/config/delete", h.AdminConfig.Delete)
	admin.POST("/config/refresh-cache", h.AdminConfig.RefreshCache)

	// Admin group routes (admin required)
	admin.POST("/group/create", h.AdminGroup.Create)
	admin.POST("/group/update", h.AdminGroup.Update)
	admin.POST("/group/delete", h.AdminGroup.Delete)
	admin.POST("/group/list", h.AdminGroup.List)
	admin.POST("/group/detail", h.AdminGroup.Detail)
	admin.POST("/group/set-resources", h.AdminGroup.SetResources)
	admin.POST("/group/set-user", h.AdminGroup.SetUserGroup)

	// Douban proxy routes (auth required)
	douban := api.Group("/douban")
	douban.Use(authMid.Auth())
	douban.POST("/subjects", h.Douban.Subjects)
	douban.POST("/tags", h.Douban.Tags)
	//douban.POST("/subject-abstract", h.Douban.SubjectAbstract)
	//douban.POST("/subject-detail", h.Douban.SubjectDetail)
	//douban.POST("/top250", h.Douban.Top250)
	//douban.POST("/search-suggest", h.Douban.SearchSuggest)
	//douban.POST("/reviews", h.Douban.Reviews)
	//douban.POST("/comments", h.Douban.Comments)
	//douban.POST("/photos", h.Douban.Photos)
	//douban.POST("/celebrities", h.Douban.Celebrities)

	// Image proxy route (uses TempTokenAuth middleware, not JWT)
	// Rate limit only applies to douban image proxy
	api.GET("/douban/image/proxy", h.Douban.ImageProxy,
		middleware.NewTempTokenAuth(cacheInstance),
		middleware.RateLimitWithConfig(middleware.RateLimitConfig{
			Max:    1000,
			Window: 1 * time.Minute,
		}),
	)

	// Resource routes (auth required)
	resource := api.Group("/resource")
	resource.Use(authMid.Auth())
	resource.POST("/sites", h.Resource.ListSites)
	resource.POST("/subscribe/config", h.Resource.GetSubscribeConfig)
	resource.POST("/search", h.Resource.Search)
	resource.POST("/detail", h.Resource.Detail)
	resource.POST("/paginate", h.Resource.Paginate)

	// Resource image proxy (public - no token needed)
	api.GET("/resource/image/proxy", h.Resource.ImageProxy)

	// Admin resource routes (admin required)
	adminResource := api.Group("/admin/resource")
	adminResource.Use(authMid.AuthAdmin())
	adminResource.POST("/subscribe/config", h.Resource.AdminGetSubscribeConfig)
	adminResource.POST("/subscribe/update", h.Resource.AdminUpdateSubscribeConfig)
	adminResource.POST("/subscribe/fetch", h.Resource.AdminFetchSubscribe)
	adminResource.POST("/proxy/test", h.Resource.ProxyTest)

	// User data routes (auth required) - 搜索历史 + 播放历史 + 收藏
	userData := api.Group("/user/data")
	userData.Use(authMid.Auth())
	// 搜索历史
	userData.POST("/search-history/list", h.UserData.SearchHistoryList)
	userData.POST("/search-history/add", h.UserData.SearchHistoryAdd)
	userData.POST("/search-history/delete", h.UserData.SearchHistoryDelete)
	userData.POST("/search-history/clear", h.UserData.SearchHistoryClear)
	// 播放历史
	userData.POST("/play-history/list", h.UserData.PlayHistoryList)
	userData.POST("/play-history/get", h.UserData.PlayHistoryGet)
	userData.POST("/play-history/upsert", h.UserData.PlayHistoryUpsert)
	userData.POST("/play-history/progress", h.UserData.PlayHistoryProgress)
	userData.POST("/play-history/delete", h.UserData.PlayHistoryDelete)
	userData.POST("/play-history/clear", h.UserData.PlayHistoryClear)
	// 收藏
	userData.POST("/favorites/list", h.UserData.FavoritesList)
	userData.POST("/favorites/add", h.UserData.FavoritesAdd)
	userData.POST("/favorites/remove", h.UserData.FavoritesRemove)
	userData.POST("/favorites/toggle", h.UserData.FavoritesToggle)
	userData.POST("/favorites/check", h.UserData.FavoritesCheck)
	userData.POST("/favorites/clear", h.UserData.FavoritesClear)

	// Download routes (auth required)
	download := api.Group("/download")
	download.Use(authMid.Auth())
	download.POST("/create", h.Download.Create)
	download.POST("/list", h.Download.List)
	download.POST("/cancel", h.Download.Cancel)
	download.POST("/delete", h.Download.Delete)
	download.POST("/retry", h.Download.Retry)
	download.POST("/check", h.Download.Check)
	// 流式播放已下载文件（需要 auth，通过 URL param 传递 task_id）
	download.GET("/file/:id", h.Download.File)

	// Admin download routes (admin required)
	adminDownload := api.Group("/admin/download")
	adminDownload.Use(authMid.AuthAdmin())
	adminDownload.POST("/list", h.Download.AdminList)
	adminDownload.POST("/config", h.Download.AdminGetConfig)
	adminDownload.POST("/config/update", h.Download.AdminUpdateConfig)

	// Temp token route (auth required - generates temporary token for URL-based auth)
	token := api.Group("/token")
	token.Use(authMid.Auth())
	token.POST("/temp", h.TempToken.Generate)

	// Stream proxy routes - split by auth method
	// ProxyM3U8/ProxyKey/ProxyTS use TempTokenAuth (URL token for Apple TV etc.)
	streamProxy := api.Group("/stream/proxy")
	streamProxy.Use(middleware.NewTempTokenAuth(cacheInstance))
	streamProxy.GET("/m3u8", h.Stream.ProxyM3U8)
	streamProxy.GET("/key", h.Stream.ProxyKey)
	streamProxy.GET("/ts", h.Stream.ProxyTS)

	// Stream management routes use JWT Auth
	stream := api.Group("/stream")
	stream.Use(authMid.Auth())
	stream.POST("/check", h.Stream.CheckM3U8)
	//stream.POST("/save", h.Stream.Save)
	stream.DELETE("/session", h.Stream.Close)

	return e
}

func healthHandler(c echo.Context) error {
	return c.JSON(200, map[string]string{"status": "ok"})
}
