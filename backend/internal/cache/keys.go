package cache

import (
	"fmt"
	"time"
)

// CacheKey binds a cache key with its TTL.
// Using this pattern ensures TTL is always carried with the key.
type CacheKey struct {
	Key string
	TTL time.Duration
}

// Prefix constants for namespace separation.
const (
	PrefixUser       = "user"
	PrefixVideo      = "video"
	PrefixAuth       = "auth"
	PrefixToken      = "token"
	PrefixCode       = "code"
	PrefixSysConfig  = "sys_config"
	PrefixDouban     = "douban"
	PrefixTempToken  = "tmp_token"
	PrefixResource   = "resource"
	PrefixUserGroup  = "user_group"
	PrefixFavorite   = "fav"
	PrefixDoubanRank = "douban_rank"
)

// TTL constants for common cache entries.
const (
	TTLUserDetail         = 30 * time.Minute
	TTLVideoList          = 5 * time.Minute
	TTLVideoDetail        = 10 * time.Minute
	TTLTokenBlack         = 24 * time.Hour
	TTLLoginCode          = 5 * time.Minute
	TTLRateLimit          = 1 * time.Minute
	TTLSysConfig          = 5 * time.Minute
	TTLDoubanJSON         = 30 * time.Minute
	TTLTempToken          = 3 * time.Hour  // 临时 token 默认有效期
	TTLTempTokenMax       = 12 * time.Hour // 临时 token 最长有效期（含续期）
	TTLResourceSite       = 30 * time.Minute
	TTLUserGroupResources = 30 * time.Minute
	TTLUserGroupID        = 30 * time.Minute
	TTLResourceSearch     = 5 * time.Minute
	TTLResourceDetail     = 10 * time.Minute
	TTLFavoriteCheck      = 30 * time.Minute
	TTLDoubanRank         = 10 * time.Minute
	TTLLoginFail          = 15 * time.Minute   // 登录失败计数窗口
	TTLDeviceSession      = 30 * time.Minute   // 设备会话心跳超时（默认值，实际从配置读取）
	TTLUserDevices        = 7 * 24 * time.Hour // 用户设备汇总索引
)

// Key generators - bind key pattern with TTL.

// KeyUserDetail generates a cache key for user detail.
var KeyUserDetail = func(id int64) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:detail:%d", PrefixUser, id),
		TTL: TTLUserDetail,
	}
}

// KeyVideoDetail generates a cache key for video detail.
var KeyVideoDetail = func(id int64) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:detail:%d", PrefixVideo, id),
		TTL: TTLVideoDetail,
	}
}

// KeyVideoList generates a cache key for video list.
var KeyVideoList = func(page, size int, category string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:list:%d:%d:%s", PrefixVideo, page, size, category),
		TTL: TTLVideoList,
	}
}

// KeyVideoSearch generates a cache key for video search results.
var KeyVideoSearch = func(keyword string, page int) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:search:%s:%d", PrefixVideo, keyword, page),
		TTL: TTLVideoList,
	}
}

// KeyTokenBlack generates a cache key for JWT token blacklist.
var KeyTokenBlack = func(jti string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:black:%s", PrefixToken, jti),
		TTL: TTLTokenBlack,
	}
}

// KeyLoginCode generates a cache key for login verification code.
var KeyLoginCode = func(code string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:code:%s", PrefixCode, code),
		TTL: TTLLoginCode,
	}
}

// KeyRateLimit generates a cache key for rate limiting.
var KeyRateLimit = func(identifier string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("ratelimit:%s", identifier),
		TTL: TTLRateLimit,
	}
}

// KeyDeviceSession generates a cache key for a device session.
// Key format: user:device:session:{uid}:{dt}:{deviceID}
// TTL is configurable (default 30min), passed as parameter.
var KeyDeviceSession = func(uid int64, deviceType int8, deviceID string, ttl time.Duration) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:device:session:%d:%d:%s", PrefixUser, uid, deviceType, deviceID),
		TTL: ttl,
	}
}

// KeyUserDevices generates a cache key for user devices summary index.
// Key format: user:devices:{uid}
var KeyUserDevices = func(uid int64) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:devices:%d", PrefixUser, uid),
		TTL: TTLUserDevices,
	}
}

// KeySysConfig generates a cache key for a single sys_config entry.
var KeySysConfig = func(key string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:%s", PrefixSysConfig, key),
		TTL: TTLSysConfig,
	}
}

// KeySysConfigGroup generates a cache key for a sys_config group list.
var KeySysConfigGroup = func(group string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:group:%s", PrefixSysConfig, group),
		TTL: TTLSysConfig,
	}
}

// KeyDoubanJSON generates a cache key for a douban JSON proxy response.
var KeyDoubanJSON = func(path string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:json:%s", PrefixDouban, path),
		TTL: TTLDoubanJSON,
	}
}

// KeyTempToken generates a cache key for a temporary token.
var KeyTempToken = func(token string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:%s", PrefixTempToken, token),
		TTL: TTLTempToken,
	}
}

// KeyResourceSite generates a cache key for the resource site list.
var KeyResourceSite = func() CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:site:list", PrefixResource),
		TTL: TTLResourceSite,
	}
}

// KeyUserGroupResources generates a cache key for a user group's resource config_keys.
var KeyUserGroupResources = func(groupID int64) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:resources:%d", PrefixUserGroup, groupID),
		TTL: TTLUserGroupResources,
	}
}

// KeyUserGroupID generates a cache key for a user's group_id.
var KeyUserGroupID = func(userID int64) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:groupid:%d", PrefixUserGroup, userID),
		TTL: TTLUserGroupID,
	}
}

// KeyResourceSearch generates a cache key for resource search results.
var KeyResourceSearch = func(domain, queryHash string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:search:%s:%s", PrefixResource, domain, queryHash),
		TTL: TTLResourceSearch,
	}
}

// KeyResourceDetail generates a cache key for resource detail.
var KeyResourceDetail = func(domain string, vodID int64) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:detail:%s:%d", PrefixResource, domain, vodID),
		TTL: TTLResourceDetail,
	}
}

// KeyFavoriteCheck generates a cache key for favorite check.
// Uses "v:" prefix for vodID+resourceDomain lookup, "d:" prefix for doubanID lookup,
// matching the repository's query logic.
var KeyFavoriteCheck = func(userID int64, vodID int64, resourceDomain, doubanID string) CacheKey {
	var key string
	if doubanID != "" {
		key = fmt.Sprintf("%s:check:%d:d:%s", PrefixFavorite, userID, doubanID)
	} else {
		key = fmt.Sprintf("%s:check:%d:v:%d:%s", PrefixFavorite, userID, vodID, resourceDomain)
	}
	return CacheKey{Key: key, TTL: TTLFavoriteCheck}
}

// KeyLoginFailCount generates a cache key for login failure count.
// Uses IP + username to track failed login attempts for brute-force protection.
var KeyLoginFailCount = func(ip, username string) CacheKey {
	return CacheKey{
		Key: fmt.Sprintf("%s:login_fail:%s:%s", PrefixAuth, ip, username),
		TTL: TTLLoginFail,
	}
}
