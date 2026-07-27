package config

import (
	"fmt"
	"time"

	"gorm.io/driver/mysql"
	"gorm.io/driver/postgres"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"

	"cn.meow/meowtv/internal/model/entity"
)

// Config is the root configuration structure.
type Config struct {
	App        AppConfig        `mapstructure:"app"`
	DB         DBConfig         `mapstructure:"db"`
	Cache      CacheConfig      `mapstructure:"cache"`
	Auth       AuthConfig       `mapstructure:"auth"`
	Server     ServerConfig     `mapstructure:"server"`
	Log        LogConfig        `mapstructure:"log"`
	Encryption EncryptionConfig `mapstructure:"encryption"`
	HTTPClient HTTPClientConfig `mapstructure:"http_client"`
}

// AppConfig holds application-level settings.
type AppConfig struct {
	Name  string `mapstructure:"name"`
	Env   string `mapstructure:"env"` // dev / prod
	Debug bool   `mapstructure:"debug"`
}

// DBConfig holds database connection settings.
type DBConfig struct {
	Driver   string          `mapstructure:"driver"`   // sqlite / mysql / postgres
	DSN      string          `mapstructure:"dsn"`      // Full DSN string (takes priority if non-empty)
	Host     string          `mapstructure:"host"`     // mysql/postgres: host address
	Port     int             `mapstructure:"port"`     // mysql/postgres: port number
	User     EncryptedString `mapstructure:"user"`     // mysql/postgres: username (supports ENC: prefix)
	Password EncryptedString `mapstructure:"password"` // mysql/postgres: password (supports ENC: prefix)
	DBName   string          `mapstructure:"dbname"`   // mysql/postgres: database name
	SSLMode  string          `mapstructure:"sslmode"`  // postgres: disable/require/verify-full
	Charset  string          `mapstructure:"charset"`  // mysql: default utf8mb4
}

// CacheConfig holds cache settings.
type CacheConfig struct {
	Type       string           `mapstructure:"type"` // gocache / ristretto / redis / multilevel
	Local      LocalCacheConfig `mapstructure:"local"`
	Ristretto  RistrettoConfig  `mapstructure:"ristretto"`
	Redis      RedisConfig      `mapstructure:"redis"`
	MultiLevel MultiLevelConfig `mapstructure:"multilevel"`
}

// LocalCacheConfig holds settings for in-memory cache implementations.
type LocalCacheConfig struct {
	DefaultTTL      time.Duration `mapstructure:"default_ttl"`
	CleanupInterval time.Duration `mapstructure:"cleanup_interval"`
}

// RedisConfig holds settings for Redis.
type RedisConfig struct {
	Addr     string          `mapstructure:"addr"`
	Password EncryptedString `mapstructure:"password"`
	DB       int             `mapstructure:"db"`
}

// MultiLevelConfig holds settings for L1 (local) + L2 (Redis) multi-level cache.
type MultiLevelConfig struct {
	Local LocalCacheConfig `mapstructure:"local"`
	Redis RedisConfig      `mapstructure:"redis"`
}

// AuthConfig holds authentication settings.
type AuthConfig struct {
	JWTSecret        EncryptedString `mapstructure:"jwt_secret"`
	AccessTTL        time.Duration   `mapstructure:"access_ttl"`
	RefreshTTL       time.Duration   `mapstructure:"refresh_ttl"`
	KickEnabled      bool            `mapstructure:"kick_enabled"`
	DeviceSessionTTL time.Duration   `mapstructure:"device_session_ttl"` // 设备会话心跳超时（默认 30m）
	AdminUsername    string          `mapstructure:"admin_username"`     // Initial admin username (used only when no admin exists in DB)
	AdminPassword    EncryptedString `mapstructure:"admin_password"`     // Initial admin password (supports ENC: prefix, used only when no admin exists in DB)
}

// ServerConfig holds HTTP server settings.
type ServerConfig struct {
	Port         int           `mapstructure:"port"`
	ReadTimeout  time.Duration `mapstructure:"read_timeout"`
	WriteTimeout time.Duration `mapstructure:"write_timeout"`
	IdleTimeout  time.Duration `mapstructure:"idle_timeout"` // Keep-alive idle timeout, prevents connection leaks
	CORSOrigins  []string      `mapstructure:"cors_origins"` // Allowed CORS origins (empty = allow all for dev, restricted for prod)
}

// LogConfig holds logging settings.
type LogConfig struct {
	Console        bool   `mapstructure:"console"`         // Enable console output
	File           bool   `mapstructure:"file"`            // Enable file output
	Dir            string `mapstructure:"dir"`             // Log file directory
	FilenamePrefix string `mapstructure:"filename_prefix"` // Log filename prefix (e.g. "meowtv" → meowtv-2026-06-11.log)
	RetentionDays  int    `mapstructure:"retention_days"`  // Days to retain log files (0 = no cleanup)
}

// EncryptionConfig holds encryption settings for sensitive configuration values.
type EncryptionConfig struct {
	Key string `mapstructure:"key"` // Encryption key for decrypting ENC: prefixed values
}

// HTTPClientConfig holds HTTP client timeout settings for outbound requests.
type HTTPClientConfig struct {
	Timeout         time.Duration `mapstructure:"timeout"`          // General HTTP client timeout (default: 30s)
	StreamTimeout   time.Duration `mapstructure:"stream_timeout"`   // Stream proxy HTTP client timeout (default: 60s)
	DownloadTimeout time.Duration `mapstructure:"download_timeout"` // Download service HTTP client timeout (default: 60s)
}

// RistrettoConfig holds settings for Ristretto cache.
type RistrettoConfig struct {
	MaxCost     int64         `mapstructure:"max_cost"`     // Maximum memory cost in bytes
	BufferItems int64         `mapstructure:"buffer_items"` // Number of keys per buffer
	DefaultTTL  time.Duration `mapstructure:"default_ttl"`  // Default TTL for cache entries
}

// NewDB creates a new GORM database connection.
func NewDB(cfg *DBConfig) (*gorm.DB, error) {
	var db *gorm.DB
	var err error

	dsn := cfg.DSN
	switch cfg.Driver {
	case "sqlite":
		if dsn == "" {
			dsn = "data/meowtv.db"
		}
		db, err = gorm.Open(sqlite.Open(dsn), &gorm.Config{})

	case "mysql":
		if dsn == "" {
			dsn = cfg.buildMySQLDSN()
		}
		db, err = gorm.Open(mysql.Open(dsn), &gorm.Config{})

	case "postgres":
		if dsn == "" {
			dsn = cfg.buildPostgresDSN()
		}
		db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})

	default:
		return nil, fmt.Errorf("unsupported db driver: %s (supported: sqlite, mysql, postgres)", cfg.Driver)
	}

	if err != nil {
		return nil, fmt.Errorf("failed to connect database: %w", err)
	}

	// Auto-migrate schemas
	if err := db.AutoMigrate(&entity.User{}); err != nil {
		return nil, fmt.Errorf("failed to migrate database: %w", err)
	}

	return db, nil
}

// buildMySQLDSN builds MySQL DSN from structured fields.
// If cfg.DSN is non-empty, returns cfg.DSN directly.
// Otherwise, constructs: user:password@tcp(host:port)/dbname?charset=utf8mb4&parseTime=True&loc=Local
func (c *DBConfig) buildMySQLDSN() string {
	//if c.DSN != "" {
	//	return c.DSN
	//}
	user, _ := c.User.Plain()
	password, _ := c.Password.Plain()
	charset := c.Charset
	if charset == "" {
		charset = "utf8mb4"
	}
	return fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?charset=%s&parseTime=True&loc=Local",
		user, password, c.Host, c.Port, c.DBName, charset)
}

// buildPostgresDSN builds PostgreSQL DSN from structured fields.
// If cfg.DSN is non-empty, returns cfg.DSN directly.
// Otherwise, constructs: host=x user=y password=z dbname=w port=n sslmode=disable
func (c *DBConfig) buildPostgresDSN() string {
	//if c.DSN != "" {
	//	return c.DSN
	//}
	user, _ := c.User.Plain()
	password, _ := c.Password.Plain()
	sslmode := c.SSLMode
	if sslmode == "" {
		sslmode = "disable"
	}
	return fmt.Sprintf("host=%s user=%s password=%s dbname=%s port=%d sslmode=%s",
		c.Host, user, password, c.DBName, c.Port, sslmode)
}
