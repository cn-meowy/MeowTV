package config

import (
	"fmt"
	"log/slog"
	"os"
	"reflect"
	"strings"
	"time"

	"github.com/go-viper/mapstructure/v2"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"
)

const (
	envPrefix        = "MEOWTV"
	envEncryptionKey = "MEOWTV_ENCRYPTION_KEY"
	defaultEnv       = "dev"
	defaultPort      = 8080
)

var (
	flagEnv    string
	flagConfig string
)

// Load reads configuration from files, environment variables, and command-line flags.
// Priority: command-line flags > environment variables > environment-specific config > base config > defaults.
func Load(configPath string) (*Config, error) {
	v := viper.New()

	// 1. Set defaults
	setDefaults(v)

	// 2. Set config file path
	if configPath != "" {
		v.SetConfigFile(configPath)
	} else {
		v.AddConfigPath("configs")
		v.SetConfigName("app")
	}

	// 3. Read base config file
	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	// 4. Determine environment
	env := v.GetString("app.env")
	if env == "" {
		env = defaultEnv
	}

	// 5. Merge environment-specific config
	envConfigName := fmt.Sprintf("app.%s", env)
	v.SetConfigName(envConfigName)
	if err := v.MergeInConfig(); err != nil {
		// Environment-specific config is optional; ignore error
	}

	// 6. Bind environment variables (MEOWTV_*)
	v.SetEnvPrefix(envPrefix)
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	// 6.5. Set encryption key from environment variable (before unmarshalling)
	// Priority: env var > config file > empty
	if encKeyEnv := os.Getenv(envEncryptionKey); encKeyEnv != "" {
		SetEncryptionKey(encKeyEnv)
	}

	// 7. Bind command-line flags
	fs := pflag.NewFlagSet("meowtv", pflag.ExitOnError)
	fs.StringVarP(&flagEnv, "env", "e", "", "Environment (dev/prod)")
	fs.StringVarP(&flagConfig, "config", "c", "", "Config file path")
	_ = fs.Parse(os.Args[1:])

	// 8. Apply command-line overrides
	if flagEnv != "" {
		v.Set("app.env", flagEnv)
	}
	if flagConfig != "" {
		v.SetConfigFile(flagConfig)
		if err := v.ReadInConfig(); err != nil {
			return nil, fmt.Errorf("failed to read config file: %w", err)
		}
	}

	// 9. Unmarshal to Config struct with custom duration decoder
	var cfg Config
	if err := v.Unmarshal(&cfg, viper.DecodeHook(mapstructure.ComposeDecodeHookFunc(
		mapstructure.StringToTimeDurationHookFunc(),
		mapstructure.StringToSliceHookFunc(","),
		// Custom hook: string -> time.Duration (handles cases where Viper stores value as string)
		func(f reflect.Type, t reflect.Type, data interface{}) (interface{}, error) {
			if f.Kind() == reflect.String && t == reflect.TypeOf(time.Duration(0)) {
				s, ok := data.(string)
				if !ok {
					return data, nil
				}
				d, err := time.ParseDuration(s)
				if err != nil {
					return time.Duration(0), fmt.Errorf("invalid duration %q: %w", s, err)
				}
				return d, nil
			}
			// Custom hook: string -> EncryptedString
			if f.Kind() == reflect.String && t == reflect.TypeOf(EncryptedString("")) {
				s, ok := data.(string)
				if !ok {
					return data, nil
				}
				return EncryptedString(s), nil
			}
			return data, nil
		},
	))); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	// 9.5. If encryption key not set from env, try config file value
	if GetEncryptionKey() == "" && cfg.Encryption.Key != "" {
		SetEncryptionKey(string(cfg.Encryption.Key))
	}

	// 10. Validate production settings
	if err := validate(&cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

func setDefaults(v *viper.Viper) {
	// App defaults
	v.SetDefault("app.name", "meowTV")
	v.SetDefault("app.env", defaultEnv)
	v.SetDefault("app.debug", true)

	// Server defaults
	v.SetDefault("server.port", defaultPort)
	v.SetDefault("server.read_timeout", "60s")
	v.SetDefault("server.write_timeout", "0s")
	v.SetDefault("server.idle_timeout", "120s")

	// DB defaults (SQLite for development)
	v.SetDefault("db.driver", "sqlite")
	v.SetDefault("db.dsn", "data/meowtv.db")

	// Cache defaults (go-cache for development)
	v.SetDefault("cache.type", "gocache")
	v.SetDefault("cache.local.default_ttl", "30m")
	v.SetDefault("cache.local.cleanup_interval", "10m")

	// Auth defaults
	v.SetDefault("auth.jwt_secret", "")
	v.SetDefault("auth.access_ttl", "15m")
	v.SetDefault("auth.refresh_ttl", "168h")
	v.SetDefault("auth.kick_enabled", false)
	v.SetDefault("auth.admin_username", "admin")
	v.SetDefault("auth.admin_password", "")

	// Log defaults
	v.SetDefault("log.console", true)
	v.SetDefault("log.file", true)
	v.SetDefault("log.dir", "logs")
	v.SetDefault("log.filename_prefix", "meowtv")
	v.SetDefault("log.retention_days", 7)

	// HTTP client defaults
	v.SetDefault("http_client.timeout", "30s")
	v.SetDefault("http_client.stream_timeout", "60s")
	v.SetDefault("http_client.download_timeout", "60s")
}

func validate(cfg *Config) error {
	// Production JWT secret validation
	if cfg.App.Env == "prod" && (cfg.Auth.JWTSecret == "" || cfg.Auth.JWTSecret == EncryptedString("change-me-in-production")) {
		return fmt.Errorf("production environment requires a non-default JWT secret; set auth.jwt_secret in app.prod.yaml or via MEOWTV_AUTH_JWT_SECRET environment variable")
	}

	// Dev environment JWT secret warning
	if cfg.App.Env == "dev" && cfg.Auth.JWTSecret == "" {
		slog.Warn("JWT secret is empty in dev environment, using auto-generated secret. Set MEOWTV_AUTH_JWT_SECRET for persistent sessions.")
	}

	// Validate cache type
	validCacheTypes := map[string]bool{
		"gocache":    true,
		"ristretto":  true,
		"redis":      true,
		"multilevel": true,
	}
	if !validCacheTypes[cfg.Cache.Type] {
		return fmt.Errorf("unsupported cache type: %s (supported: gocache, ristretto, redis, multilevel)", cfg.Cache.Type)
	}

	// Validate DB driver
	validDBDrivers := map[string]bool{
		"sqlite":   true,
		"mysql":    true,
		"postgres": true,
	}
	if !validDBDrivers[cfg.DB.Driver] {
		return fmt.Errorf("unsupported DB driver: %s (supported: sqlite, mysql, postgres)", cfg.DB.Driver)
	}

	return nil
}

// GetEnv returns the current environment name.
func GetEnv() string {
	env := viper.GetString("app.env")
	if env == "" {
		return defaultEnv
	}
	return env
}

// IsProd returns true if running in production environment.
func IsProd() bool {
	return GetEnv() == "prod"
}

// IsDev returns true if running in development environment.
func IsDev() bool {
	return GetEnv() == "dev"
}

// ParseDuration parses a duration string with common time units.
func ParseDuration(s string) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil {
		return 0
	}
	return d
}
