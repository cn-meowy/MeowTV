package main

import (
	"context"
	"crypto/rand"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cn.meow/meowtv/internal/config"
	"cn.meow/meowtv/internal/logger"
	"cn.meow/meowtv/internal/migration"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/router"
	"cn.meow/meowtv/internal/wire"

	"golang.org/x/crypto/bcrypt"
)

// @title           MeowTV API
// @version         1.0
// @description     MeowTV 视频聚合平台后端 API
// @termsOfService  http://swagger.io/terms/

// @contact.name   MeowTV Support
// @contact.url    http://www.meowtv.cn

// @license.name  MIT
// @license.url   https://opensource.org/licenses/MIT

// @host      localhost:8088
// @BasePath  /api

// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization

func main() {
	// 1. Load configuration
	cfg, err := config.Load("")
	if err != nil {
		slog.Error("failed to load config", "error", err)
		os.Exit(1)
	}

	// 2. Initialize slog (console + file with daily rotation & auto cleanup)
	closeLogger := logger.Init(cfg)
	defer closeLogger()

	slog.Info("starting meowTV server",
		"env", cfg.App.Env,
		"port", cfg.Server.Port,
	)

	// 3. Initialize database
	db, err := config.NewDB(&cfg.DB)
	if err != nil {
		slog.Error("failed to initialize database", "error", err)
		os.Exit(1)
	}

	// 4. Pre-migrate: drop old indexes that need to change
	migration.MigratePlayHistoryUniqueIndex(db)

	// 5. AutoMigrate + Seed
	if err := db.AutoMigrate(
		&entity.User{}, &entity.SysConfig{}, &entity.UserGroup{}, &entity.UserGroupResource{},
		&entity.SearchHistory{}, &entity.PlayHistory{}, &entity.Favorite{},
		&entity.DownloadTask{}, &entity.DoubanRank{}, &entity.LocalVideo{},
	); err != nil {
		slog.Error("failed to auto-migrate", "error", err)
		os.Exit(1)
	}
	migration.SeedSysConfig(db)

	// Seed admin user if not exists
	var count int64
	db.Model(&entity.User{}).Where("role = ?", entity.RoleAdmin).Count(&count)
	if count == 0 {
		adminPassword, _ := cfg.Auth.AdminPassword.Plain()
		if adminPassword == "" {
			// Auto-generate a random password if not configured
			adminPassword = generateRandomPassword(16)
			slog.Info("auto-generated admin password (set MEOWTV_AUTH_ADMIN_PASSWORD for custom password)",
				"username", cfg.Auth.AdminUsername,
				"password", adminPassword,
			)
		}
		hash, _ := bcrypt.GenerateFromPassword([]byte(adminPassword), bcrypt.DefaultCost)
		admin := &entity.User{
			Username:     cfg.Auth.AdminUsername,
			PasswordHash: string(hash),
			Nickname:     "管理员",
			Role:         entity.RoleAdmin,
			Status:       entity.StatusEnabled,
		}
		db.Create(admin)
		slog.Info("seeded admin user", "username", cfg.Auth.AdminUsername)
	}

	// 6. Wire 依赖注入 — 自动构建所有依赖
	app, err := wire.InitializeApp(cfg, db)
	if err != nil {
		slog.Error("failed to initialize app", "error", err)
		os.Exit(1)
	}

	// 6.5. Demo 模式：扫描本地影视数据目录并入库（Apple Store 审核演示）
	if app.LocalDataService != nil && app.LocalDataService.IsDemoMode() {
		slog.Info("demo mode enabled, scanning local data directory", "dir", cfg.Demo.LocalDataDir)
		if err := app.LocalDataService.ScanAndSeed(context.Background()); err != nil {
			slog.Error("failed to scan demo data", "error", err)
		}
	}

	// 7. Register config change callbacks
	app.SysConfigService.RegisterOnUpdate("resource_subscribe", func(ctx context.Context) {
		if err := app.ResourceService.RestartCron(); err != nil {
			slog.Error("failed to restart cron after subscribe config update", "error", err)
		}
	})
	app.SysConfigService.RegisterOnUpdate("douban_rank_sync", func(ctx context.Context) {
		if err := app.DoubanRankService.RestartCron(); err != nil {
			slog.Error("failed to restart cron after douban rank sync config update", "error", err)
		}
	})
	app.SysConfigService.RegisterOnUpdate("stream_config", func(ctx context.Context) {
		app.StreamService.ReloadConfig()
	})

	// 9. Start background goroutines
	app.DoubanImageService.StartCleanupGoroutine()
	app.ResourceImageService.StartCleanupGoroutine()
	if err := app.DownloadService.Start(); err != nil {
		slog.Error("failed to start download service", "error", err)
		os.Exit(1)
	}
	app.StreamService.Start()

	// 10. Build Echo instance
	e := router.New(router.Config{Debug: cfg.App.Debug}, app.Handlers, app.AuthMiddleware, cfg.Server.CORSOrigins, app.CacheProvider.Cache)

	// 11. Start HTTP server
	addr := ":" + fmt.Sprintf("%d", cfg.Server.Port)
	srv := &http.Server{
		Addr:         addr,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
		IdleTimeout:  cfg.Server.IdleTimeout,
	}

	// Start resource subscribe cron
	if err := app.ResourceService.StartCron(); err != nil {
		slog.Error("failed to start resource cron", "error", err)
	}

	// Start douban rank sync cron
	if err := app.DoubanRankService.StartCron(); err != nil {
		slog.Error("failed to start douban rank cron", "error", err)
	}

	go func() {
		slog.Info("server listening", "addr", addr)
		if err := e.StartServer(srv); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	// 12. Wait for shutdown signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("shutting down server...")

	// 13. Graceful shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Stop background goroutines
	app.DownloadService.Stop()
	app.StreamService.Stop()
	app.DoubanImageService.Stop()
	app.ResourceImageService.Stop()
	app.ResourceService.StopCron()
	app.DoubanRankService.StopCron()

	// Close cache
	_ = app.CacheProvider.Cache.Close()

	if err := e.Shutdown(ctx); err != nil {
		slog.Error("server forced to shutdown", "error", err)
	}

	slog.Info("server stopped")
}

// generateRandomPassword generates a cryptographically secure random password
// using alphanumeric characters (avoiding ambiguous characters).
func generateRandomPassword(length int) string {
	const charset = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789"
	b := make([]byte, length)
	randBytes := make([]byte, length)
	_, _ = rand.Read(randBytes)
	for i := range b {
		b[i] = charset[int(randBytes[i])%len(charset)]
	}
	return string(b)
}
