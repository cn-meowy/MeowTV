package migration

import (
	"log/slog"

	"gorm.io/gorm"

	"cn.meow/meowtv/internal/model/entity"
)

// MigratePlayHistoryUniqueIndex 迁移播放历史表唯一索引：
// 旧索引 (user_id, vod_id, resource_domain) → 新索引 (user_id, vod_id, resource_domain, ep_index)
//
// SQLite 不支持 ALTER INDEX，需要先删除旧索引再让 AutoMigrate 创建新索引。
func MigratePlayHistoryUniqueIndex(db *gorm.DB) {
	m := db.Migrator()

	// 检查旧索引是否存在
	if m.HasIndex(&entity.PlayHistory{}, "uk_user_vod_resource") {
		slog.Info("[migration] dropping old unique index uk_user_vod_resource on play_histories")
		if err := m.DropIndex(&entity.PlayHistory{}, "uk_user_vod_resource"); err != nil {
			slog.Error("[migration] failed to drop old index uk_user_vod_resource", "error", err)
		}
	}
}
