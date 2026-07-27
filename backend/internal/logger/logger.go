package logger

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"

	"cn.meow/meowtv/internal/config"
)

// dailyWriter wraps a file handle that rotates daily.
type dailyWriter struct {
	mu       sync.Mutex
	dir      string
	prefix   string
	ext      string
	current  string   // current date string "2006-01-02"
	file     *os.File // current open file
	cleaners []func() // cleanup functions to call on Close
}

// newDailyWriter creates a new daily-rotating writer.
func newDailyWriter(cfg *config.LogConfig) (*dailyWriter, error) {
	dir := cfg.Dir
	if dir == "" {
		dir = "logs"
	}

	// Ensure directory exists
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("failed to create log directory %s: %w", dir, err)
	}

	w := &dailyWriter{
		dir:    dir,
		prefix: cfg.FilenamePrefix,
		ext:    ".log",
	}

	// Open initial file
	if err := w.rotate(time.Now()); err != nil {
		return nil, err
	}

	return w, nil
}

// Write implements io.Writer. It rotates the file if the date has changed.
func (w *dailyWriter) Write(p []byte) (n int, err error) {
	w.mu.Lock()
	defer w.mu.Unlock()

	today := time.Now().Format("2006-01-02")
	if today != w.current {
		if err := w.rotate(time.Now()); err != nil {
			return 0, err
		}
	}

	return w.file.Write(p)
}

// rotate closes the current file (if any) and opens a new one for the given date.
func (w *dailyWriter) rotate(t time.Time) error {
	if w.file != nil {
		_ = w.file.Close()
	}

	dateStr := t.Format("2006-01-02")
	w.current = dateStr

	var filename string
	if w.prefix != "" {
		filename = fmt.Sprintf("%s-%s%s", w.prefix, dateStr, w.ext)
	} else {
		filename = fmt.Sprintf("%s%s", dateStr, w.ext)
	}

	path := filepath.Join(w.dir, filename)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("failed to open log file %s: %w", path, err)
	}
	w.file = f
	return nil
}

// Close closes the current log file.
func (w *dailyWriter) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()

	// Run cleanup functions
	for _, fn := range w.cleaners {
		fn()
	}

	if w.file != nil {
		err := w.file.Close()
		w.file = nil
		return err
	}
	return nil
}

// Cleanup removes log files older than the specified retention days.
func Cleanup(dir string, retentionDays int) error {
	if dir == "" || retentionDays <= 0 {
		return nil
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("failed to read log directory %s: %w", dir, err)
	}

	cutoff := time.Now().AddDate(0, 0, -retentionDays)

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		// Check file modification time
		if info.ModTime().Before(cutoff) {
			path := filepath.Join(dir, entry.Name())
			if err := os.Remove(path); err != nil {
				// Log removal failure but continue with other files
				_, _ = fmt.Fprintf(os.Stderr, "failed to remove old log file %s: %v\n", path, err)
			}
		}
	}

	return nil
}

// StartCleanupRoutine starts a goroutine that periodically removes old log files.
// It returns a stop function that should be called on shutdown.
func StartCleanupRoutine(dir string, retentionDays int, interval time.Duration) func() {
	if dir == "" || retentionDays <= 0 {
		return func() {}
	}

	if interval <= 0 {
		interval = 24 * time.Hour // default: check once per day
	}

	stop := make(chan struct{})

	go func() {
		// Run cleanup immediately on start
		if err := Cleanup(dir, retentionDays); err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "log cleanup error: %v\n", err)
		}

		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				if err := Cleanup(dir, retentionDays); err != nil {
					_, _ = fmt.Fprintf(os.Stderr, "log cleanup error: %v\n", err)
				}
			case <-stop:
				return
			}
		}
	}()

	return func() { close(stop) }
}

// multiHandler distributes log records to multiple handlers.
type multiHandler struct {
	handlers []slog.Handler
}

// newMultiHandler creates a handler that fans out to multiple slog.Handlers.
func newMultiHandler(handlers ...slog.Handler) slog.Handler {
	return &multiHandler{handlers: handlers}
}

func (h *multiHandler) Enabled(ctx context.Context, level slog.Level) bool {
	for _, handler := range h.handlers {
		if handler.Enabled(ctx, level) {
			return true
		}
	}
	return false
}

func (h *multiHandler) Handle(ctx context.Context, r slog.Record) error {
	for _, handler := range h.handlers {
		if handler.Enabled(ctx, r.Level) {
			if err := handler.Handle(ctx, r.Clone()); err != nil {
				return err
			}
		}
	}
	return nil
}

func (h *multiHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	newHandlers := make([]slog.Handler, len(h.handlers))
	for i, handler := range h.handlers {
		newHandlers[i] = handler.WithAttrs(attrs)
	}
	return &multiHandler{handlers: newHandlers}
}

func (h *multiHandler) WithGroup(name string) slog.Handler {
	newHandlers := make([]slog.Handler, len(h.handlers))
	for i, handler := range h.handlers {
		newHandlers[i] = handler.WithGroup(name)
	}
	return &multiHandler{handlers: newHandlers}
}

// Init initializes the global slog logger with console and/or file output.
// It returns a cleanup function that should be called on shutdown.
func Init(cfg *config.Config) func() {
	logCfg := &cfg.Log

	var level slog.Level
	if cfg.App.Debug {
		level = slog.LevelDebug
	} else {
		level = slog.LevelInfo
	}

	opts := &slog.HandlerOptions{
		Level: level,
	}

	var handlers []slog.Handler
	var closers []func()

	// Console handler — use TextHandler in dev for readability, JSONHandler in prod
	if logCfg.Console {
		if cfg.App.Env == "prod" {
			handlers = append(handlers, slog.NewJSONHandler(os.Stdout, opts))
		} else {
			handlers = append(handlers, slog.NewTextHandler(os.Stdout, opts))
		}
	}

	// File handler — always JSON format with daily rotation
	if logCfg.File {
		writer, err := newDailyWriter(logCfg)
		if err != nil {
			_, _ = fmt.Fprintf(os.Stderr, "failed to init file logger: %v, falling back to console only\n", err)
		} else {
			handlers = append(handlers, slog.NewJSONHandler(writer, opts))

			// Start cleanup routine for old log files
			retentionDays := logCfg.RetentionDays
			if retentionDays <= 0 {
				retentionDays = 7
			}
			stopCleanup := StartCleanupRoutine(logCfg.Dir, retentionDays, 24*time.Hour)
			closers = append(closers, stopCleanup)
			closers = append(closers, func() { _ = writer.Close() })
		}
	}

	// Fallback: if no handlers configured, use console
	if len(handlers) == 0 {
		handlers = append(handlers, slog.NewTextHandler(os.Stdout, opts))
	}

	var handler slog.Handler
	if len(handlers) == 1 {
		handler = handlers[0]
	} else {
		handler = newMultiHandler(handlers...)
	}

	slog.SetDefault(slog.New(handler))

	return func() {
		for _, fn := range closers {
			fn()
		}
	}
}

// ensure dailyWriter implements io.Writer
var _ io.Writer = (*dailyWriter)(nil)
