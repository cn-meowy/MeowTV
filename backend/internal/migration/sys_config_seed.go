package migration

import (
	"log/slog"

	"gorm.io/gorm"

	"cn.meow/meowtv/internal/model/entity"
)

// SeedSysConfig 初始化 sys_config 表的默认数据
// demoEnabled 表示是否启用了 demo 模式（配置了本地数据目录），
// 仅在启用时才写入本地演示资源站点，避免未配置本地目录时加载"本地资源"。
func SeedSysConfig(db *gorm.DB, demoEnabled bool) {
	configs := []entity.SysConfig{
		// --- JSON 数据通道配置 ---
		{
			ConfigKey:   "douban_json_channel",
			ConfigGroup: "douban",
			Title:       "豆瓣JSON数据通道",
			Title1:      "直连地址", Value1: "https://movie.douban.com",
			Title2: "备用CORS代理", Value2: "https://zwei.de",
			Title3: "当前通道(1=直连,2=CORS代理)", Value3: "1",
			Title4: "请求超时(秒)", Value4: "10",
			Title5: "重试次数", Value5: "2",
			SortOrder: 1,
			IsEnabled: true,
		},
		// --- 图片分流节点配置 ---
		{
			ConfigKey:   "douban_image_node_img1",
			ConfigGroup: "douban",
			Title:       "图片分流节点-img1",
			Title1:      "节点前缀", Value1: "https://img1.doubanio.com",
			Title2: "优先级", Value2: "1",
			Title3: "用途说明", Value3: "条目缩略小图、列表迷你封面",
			Title4: "启用", Value4: "true",
			SortOrder: 2,
			IsEnabled: true,
		},
		{
			ConfigKey:   "douban_image_node_img2",
			ConfigGroup: "douban",
			Title:       "图片分流节点-img2",
			Title1:      "节点前缀", Value1: "https://img2.doubanio.com",
			Title2: "优先级", Value2: "2",
			Title3: "用途说明", Value3: "小组、广播、动态中等尺寸配图",
			Title4: "启用", Value4: "true",
			SortOrder: 3,
			IsEnabled: true,
		},
		{
			ConfigKey:   "douban_image_node_img3",
			ConfigGroup: "douban",
			Title:       "图片分流节点-img3",
			Title1:      "节点前缀", Value1: "https://img3.doubanio.com",
			Title2: "优先级", Value2: "3",
			Title3: "用途说明", Value3: "高清大图、相册原图、剧照",
			Title4: "启用", Value4: "true",
			SortOrder: 4,
			IsEnabled: true,
		},
		{
			ConfigKey:   "douban_image_node_img9",
			ConfigGroup: "douban",
			Title:       "图片分流节点-img9",
			Title1:      "节点前缀", Value1: "https://img9.doubanio.com",
			Title2: "优先级", Value2: "1",
			Title3: "用途说明", Value3: "新版影视/图书条目标准封面",
			Title4: "启用", Value4: "true",
			SortOrder: 5,
			IsEnabled: true,
		},
		// --- 图片代理配置 ---
		{
			ConfigKey:   "douban_image_proxy",
			ConfigGroup: "douban",
			Title:       "图片代理配置",
			Title1:      "启用图片缓存", Value1: "true",
			Title2: "缓存目录", Value2: "./data/douban_images",
			Title3: "缓存天数", Value3: "7",
			Title4: "清理间隔(小时)", Value4: "1",
			Title5: "分流节点白名单(JSON数组)", Value5: `["img.doubanio.com","img1.doubanio.com","img2.doubanio.com","img3.doubanio.com","img9.doubanio.com"]`,
			SortOrder: 6,
			IsEnabled: true,
		},
		// --- 限流配置 ---
		{
			ConfigKey:   "douban_rate_limit",
			ConfigGroup: "douban",
			Title:       "豆瓣请求限流",
			Title1:      "每秒请求数(QPS)", Value1: "5",
			Title2: "客户端每分钟请求上限", Value2: "30",
			SortOrder: 7,
			IsEnabled: true,
		},
		// --- 缓存配置 ---
		{
			ConfigKey:   "douban_cache",
			ConfigGroup: "douban",
			Title:       "豆瓣数据缓存",
			Title1:      "JSON缓存时长(分钟)", Value1: "30",
			Title2: "启用JSON缓存", Value2: "true",
			SortOrder: 8,
			IsEnabled: true,
		},
		// --- 资源订阅配置 ---
		{
			ConfigKey:   "resource_subscribe",
			ConfigGroup: "resource_subscribe",
			Title:       "资源订阅配置",
			Title1:      "订阅地址", Value1: "",
			Title2: "开启自动订阅", Value2: "false",
			Title3: "Cron表达式", Value3: "0 */6 * * * ?",
			SortOrder: 1,
			IsEnabled: true,
		},
		// --- 资源代理配置 ---
		{
			ConfigKey:   "resource_proxy",
			ConfigGroup: "resource_subscribe",
			Title:       "资源代理配置",
			Title1:      "代理协议", Value1: "socks5",
			Title2: "代理地址", Value2: "127.0.0.1",
			Title3: "代理端口", Value3: "1080",
			Title4: "认证用户名", Value4: "",
			Title5: "认证密码", Value5: "",
			Title6: "启用代理", Value6: "false",
			SortOrder: 2,
			IsEnabled: true,
		},
		// --- 代理测试URL配置 ---
		{
			ConfigKey:   "resource_proxy_test_url",
			ConfigGroup: "resource_subscribe",
			Title:       "代理测试URL",
			Title1:      "测试URL", Value1: "http://www.gstatic.com/generate_204",
			SortOrder: 3,
			IsEnabled: true,
		},
		// --- 豆瓣榜单同步配置 ---
		{
			ConfigKey:   "douban_rank_sync",
			ConfigGroup: "douban",
			Title:       "豆瓣榜单同步配置",
			Title1:      "启用自动同步", Value1: "true",
			Title2: "Cron表达式", Value2: "0 0 6 * * ?",
			Title3: "数据保留日期数", Value3: "2",
			Title4: "同步请求间隔(毫秒)", Value4: "500",
			Title5: "同步每页条数", Value5: "20",
			SortOrder: 9,
			IsEnabled: true,
		},
		// --- 流代理配置 ---
		{
			ConfigKey:   "stream_config",
			ConfigGroup: "stream",
			Title:       "流代理配置",
			Title1:      "前瞻窗口大小", Value1: "20",
			Title2: "通用协程数量", Value2: "5",
			Title3: "总协程上限", Value3: "8",
			Title4: "自动保存", Value4: "false",
			Title5: "启用流代理", Value5: "false",
			Title6: "磁盘缓存上限(MB)", Value6: "10240",
			SortOrder: 1,
			IsEnabled: true,
		},
		// --- 首页区块标题配置 ---
		{
			ConfigKey:   "home_section_titles",
			ConfigGroup: "home",
			Title:       "首页区块标题",
			Title1:      "区块一标题", Value1: "热门影视",
			Title2: "区块二标题", Value2: "热播剧集",
			SortOrder: 1,
			IsEnabled: true,
		},
		// --- 本地演示资源站点（Apple Store 审核演示模式，demo 模式自动启用） ---
		// 仅在 demo 模式（配置了本地数据目录）下写入，避免未指定目录时加载"本地资源"。
	}

	// demo 模式启用时才追加本地演示资源站点配置
	if demoEnabled {
		configs = append(configs, entity.SysConfig{
			ConfigKey:   "local_demo_domain",
			ConfigGroup: "resource_site",
			Title:       "本地演示资源",
			Value1:      "local://demo",
			Value2:      "local://demo",
			Value3:      "Apple Store 审核演示本地数据",
			Value4:      "0",
			Value5:      "0", // 非NSFW
			Value6:      "1", // 允许搜索
			SortOrder:   999,
			IsEnabled:   true,
			Remark:      "本地演示虚拟站点，数据来自 MEOWTV_DEMO_DATA_DIR 扫描",
		})
	}

	seeded := 0
	for _, cfg := range configs {
		// 按 config_key 逐条检查，不存在才插入
		var count int64
		db.Model(&entity.SysConfig{}).Where("config_key = ?", cfg.ConfigKey).Count(&count)
		if count > 0 {
			continue
		}
		if err := db.Create(&cfg).Error; err != nil {
			slog.Error("failed to seed sys_config", "key", cfg.ConfigKey, "error", err)
		} else {
			seeded++
		}
	}

	if seeded > 0 {
		slog.Info("sys_config seeded successfully", "count", seeded)
	}
}
