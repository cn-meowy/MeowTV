# MeowTV 前后端接口对接文档

> 版本：v1.0.0
> 更新日期：2026-06-22
> 项目：MeowTV 全栈视频平台

---

## 1. 概述

### 1.1 项目简介

MeowTV 是一个全栈视频平台后端服务，基于 Go 语言（Echo 框架）构建，提供影视资源聚合、搜索、播放历史管理、下载管理等功能。

### 1.2 文档目的

本文档旨在为其他客户端（移动端、小程序、Web 其他端）提供统一的前后端接口对接规范，确保各端接入流程一致、接口调用规范统一。

### 1.3 Base URL 与环境说明

| 环境 | Base URL |
|------|----------|
| 开发环境 | `http://localhost:5173`（前端）/ `http://localhost:8080`（后端） |
| 生产环境 | `https://your-domain.com` |

**接口 Base URL**：`{host}/api`

### 1.4 认证方式

本系统采用 **JWT Bearer Token** 进行身份认证。

#### 请求头

```
Authorization: Bearer <access_token>
```

#### Token 类型

| Token 类型 | 用途 | 有效期 |
|-----------|------|--------|
| `access_token` | API 访问凭证 | 2 小时（7200 秒） |
| `refresh_token` | 刷新 access_token | 7 天 |

#### Token 获取流程

1. 用户登录成功 → 返回 `access_token` + `refresh_token`
2. 后续请求携带 `access_token`
3. `access_token` 过期前 → 调用 `/api/auth/refresh` 获取新 Token
4. `refresh_token` 过期 → 需重新登录

### 1.5 统一响应格式

所有接口统一返回以下 JSON 格式：

```json
{
  "code": 200,
  "msg": "success",
  "data": { ... }
}
```

#### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `code` | int | 状态码，200 表示成功，其他表示错误 |
| `msg` | string | 状态信息 |
| `data` | object/null | 响应数据，失败时通常为 null |

#### 通用错误码

| code | 说明 |
|------|------|
| 200 | 成功 |
| 400 | 请求参数错误 |
| 401 | 未授权（Token 无效或过期） |
| 403 | 权限不足 |
| 404 | 资源不存在 |
| 500 | 服务器内部错误 |

### 1.6 通用请求头

| 请求头 | 值 | 必填 |
|--------|-----|------|
| `Content-Type` | `application/json` | 是 |
| `Authorization` | `Bearer <token>` | 除公开接口外均需 |

### 1.7 device_type 枚举值

| 值 | 说明 |
|-----|------|
| 0 | Web 浏览器 |
| 1 | Android 移动端 |
| 2 | iOS 移动端 |
| 3 | Apple TV 设备 |

### 1.8 role 角色说明

| 值 | 说明 |
|-----|------|
| 0 | 普通用户 |
| 1 | 管理员 |

### 1.9 status 状态说明

| 值 | 说明 |
|-----|------|
| 0 | 正常/启用 |
| 1 | 禁用 |

---

## 2. 接口模块

---

## 2.1 认证模块 `/api/auth`

认证模块提供用户登录、登出、Token 刷新、QR 码登录等功能。

### 2.1.1 账号密码登录

**接口**：`POST /api/auth/login`

**认证**：否

**请求参数**：

| 参数 | 类型 | 必填 | 约束 | 说明 |
|------|------|------|------|------|
| `username` | string | 是 | 3-50 字符 | 用户名 |
| `password` | string | 是 | 6-50 字符 | 密码 |
| `device_type` | int8 | 是 | 0-3 | 设备类型，见 1.7 |

**请求示例**：

```json
{
  "username": "admin",
  "password": "123456",
  "device_type": 0
}
```

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `access_token` | string | 访问令牌 |
| `refresh_token` | string | 刷新令牌 |
| `expires_in` | int64 | 有效期（秒） |

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 7200
  }
}
```

---

### 2.1.2 刷新 Token

**接口**：`POST /api/auth/refresh`

**认证**：否

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `refresh_token` | string | 是 | 刷新令牌 |

**请求示例**：

```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**响应参数**：同登录响应

---

### 2.1.3 登出

**接口**：`POST /api/auth/logout`

**认证**：是（从 Token 中提取用户信息）

**请求参数**：无

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": null
}
```

---

### 2.1.4 QR 码登录 - TV 请求二维码

**接口**：`POST /api/auth/qrcode/request`

**认证**：否

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `device_id` | string | 是 | 设备唯一标识 |

**请求示例**：

```json
{
  "device_id": "TV-001-XXXX"
}
```

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `code` | string | 8 位登录码（大写字母+数字，字符集 ABCDEFGHJKMNPQRSTUVWXYZ23456789） |
| `qr_url` | string | 二维码内容，格式 `meowtv://qr-login?code=XXXXXXXX` |
| `expires_in` | int64 | 过期剩余秒数 |

---

### 2.1.5 QR 码登录 - 移动端扫码

**接口**：`POST /api/auth/qrcode/scan`

**认证**：是

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string | 是 | 8 位登录码 |

**请求示例**：

```json
{
  "code": "K3MNP9XR"
}
```

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": null
}
```

---

### 2.1.6 QR 码登录 - TV 端轮询结果

**接口**：`POST /api/auth/qrcode/poll`

**认证**：否

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | string | 是 | 8 位登录码 |

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `status` | int | 0=待扫码 1=已扫码 2=已确认 |
| `access_token` | string | 已确认时返回 |
| `refresh_token` | string | 已确认时返回 |
| `expires_in` | int64 | 已确认时返回 |

---

## 2.2 用户模块 `/api/user`

用户模块提供个人资料管理、设备管理等功能。

**认证**：全部需要

### 2.2.1 获取个人资料

**接口**：`POST /api/user/profile`

**请求参数**：无

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `id` | int64 | 用户 ID |
| `username` | string | 用户名 |
| `nickname` | string | 昵称 |
| `avatar` | string | 头像 URL |
| `role` | int8 | 角色，见 1.8 |
| `status` | int8 | 状态，见 1.9 |
| `group_id` | int64 | 用户组 ID |
| `group_name` | string | 用户组名称 |

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "id": 1,
    "username": "admin",
    "nickname": "管理员",
    "avatar": "https://example.com/avatar.jpg",
    "role": 1,
    "status": 0,
    "group_id": 1,
    "group_name": "默认组"
  }
}
```

---

### 2.2.2 更新个人资料

**接口**：`POST /api/user/update`

**请求参数**：

| 参数 | 类型 | 必填 | 约束 | 说明 |
|------|------|------|------|------|
| `nickname` | string | 否 | 1-50 字符 | 昵称 |
| `avatar` | string | 否 | 最大 500 字符 | 头像 URL |

**请求示例**：

```json
{
  "nickname": "新昵称",
  "avatar": "https://example.com/new-avatar.jpg"
}
```

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": null
}
```

---

### 2.2.3 修改密码

**接口**：`POST /api/user/password`

**请求参数**：

| 参数 | 类型 | 必填 | 约束 | 说明 |
|------|------|------|------|------|
| `old_password` | string | 是 | 6-50 字符 | 旧密码 |
| `new_password` | string | 是 | 6-50 字符 | 新密码 |

**请求示例**：

```json
{
  "old_password": "old123456",
  "new_password": "new123456"
}
```

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": null
}
```

---

### 2.2.4 获取在线设备列表

**接口**：`POST /api/user/devices`

**请求参数**：无

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `devices` | array | 设备列表 |
| `devices[].jti` | string | 设备会话 ID |
| `devices[].device_type` | int8 | 设备类型，见 1.7 |

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "devices": [
      {
        "jti": "abc123...",
        "device_type": 0
      }
    ]
  }
}
```

---

### 2.2.5 踢出设备

**接口**：`POST /api/user/kick-device`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `jti` | string | 是 | 设备会话 ID |

**请求示例**：

```json
{
  "jti": "abc123..."
}
```

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": null
}
```

---

## 2.3 资源搜索模块 `/api/resource`

资源搜索模块提供资源站点列表、聚合搜索、资源详情等功能。

### 2.3.1 获取资源站点列表

**接口**：`POST /api/resource/sites`

**认证**：是

**请求参数**：无

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `sites` | array | 资源站点列表 |
| `sites[].domain` | string | 资源站点域名（key） |
| `sites[].name` | string | 资源站点名称 |
| `sites[].api` | string | 资源站 API 地址 |
| `sites[].detail` | string | 资源站详情页地址 |
| `sites[].is_enabled` | bool | 是否启用 |
| `sites[].is_adult` | bool | 是否为成人站点 |
| `sites[].searchable` | bool | 是否可搜索 |

**响应示例**：

```json
{
  "code": 200,
  "msg": "success",
  "data": {
    "sites": [
      {
        "domain": "example.com",
        "name": "示例资源站",
        "api": "https://example.com/api.php/provide/vod/",
        "detail": "https://example.com",
        "is_enabled": true,
        "is_adult": false,
        "searchable": true
      }
    ]
  }
}
```

---

### 2.3.2 聚合搜索（SSE 流式）

**接口**：`POST /api/resource/search`

**认证**：是

**描述**：该接口采用 Server-Sent Events（SSE）流式返回搜索结果。

**请求参数**：

| 参数 | 类型 | 必填 | 约束 | 说明 |
|------|------|------|------|------|
| `q` | string | 是 | 最大 200 字符 | 搜索关键词 |
| `douban_id` | string | 否 | | 豆瓣 ID（可选，用于精准匹配） |
| `resources` | array | 否 | 最多 50 项 | 指定搜索的资源站点 |

**请求示例**：

```json
{
  "q": "复仇者联盟",
  "douban_id": "1295030",
  "resources": ["douban"]
}
```

**SSE 响应格式**：

```
event: result
data: {"resource_domain":"example.com","vod_id":1,"vod_name":"复仇者联盟","vod_pic":"...","type_name":"动作","remarks":"HD"}

event: result
data: {"resource_domain":"example.com","vod_id":2,"vod_name":"复仇者联盟2","vod_pic":"...","type_name":"动作","remarks":"1080P"}

event: done
data: {"resource_domain":"example.com","count":2}

event: complete
data: {"total":10}

event: error
data: {"resource_domain":"other.com","message":"连接超时"}
```

**事件类型**：

| 事件 | 说明 |
|------|------|
| `result` | 单条搜索结果 |
| `done` | 单个资源站搜索完成，包含该站结果数 |
| `complete` | 全部资源站搜索完成，包含总结果数 |
| `error` | 搜索错误 |

**result 事件数据字段**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `resource_domain` | string | 资源站域名 |
| `vod_id` | int64 | 资源 ID |
| `vod_name` | string | 资源名称 |
| `vod_pic` | string | 封面图 |
| `type_name` | string | 类型 |
| `remarks` | string | 备注信息（如清晰度） |
| `douban_id` | string | 豆瓣 ID（可选） |

---

### 2.3.3 获取资源详情

**接口**：`POST /api/resource/detail`

**认证**：是

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `site` | string | 是 | 资源站点 key |
| `vod_id` | int64 | 是 | 资源 ID |

**请求示例**：

```json
{
  "site": "douban",
  "vod_id": 1295030
}
```

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `vod_id` | int64 | 资源 ID |
| `vod_name` | string | 资源名称 |
| `vod_pic` | string | 封面图 |
| `type_name` | string | 类型（电影/剧集） |
| `vod_year` | string | 年份 |
| `vod_area` | string | 地区 |
| `vod_actor` | string | 演员 |
| `vod_director` | string | 导演 |
| `vod_content` | string | 简介 |
| `vod_play_list` | array | 播放源列表 |
| `vod_play_list[].name` | string | 源名称 |
| `vod_play_list[].url` | string | 播放地址 |
| `episodes` | array | 剧集列表（仅剧集） |
| `episodes[].index` | string | 集索引 |
| `episodes[].name` | string | 集名称 |

---

### 2.3.4 资源分页查询

**接口**：`POST /api/resource/paginate`

**认证**：是

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 是 | 页码（最小 1） |
| `page_size` | int | 是 | 每页数量（1-100） |
| `keyword` | string | 否 | 搜索关键词 |
| `resource` | string | 是 | 资源站点 key |

**请求示例**：

```json
{
  "page": 1,
  "page_size": 20,
  "keyword": "电影",
  "resource": "douban"
}
```

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `items` | array | 资源列表 |
| `total` | int64 | 总数 |
| `page` | int | 当前页 |
| `page_size` | int | 每页数量 |
| `total_pages` | int | 总页数 |

---

### 2.3.5 图片代理

**接口**：`GET /api/resource/image/proxy`

**认证**：否

**Query 参数**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `url` | 是 | 图片 URL |

**示例**：`GET /api/resource/image/proxy?url=https://example.com/image.jpg`

---

## 2.4 豆瓣代理模块 `/api/douban`

豆瓣代理模块提供豆瓣影视内容获取、图片代理等功能。

**认证**：全部需要

### 2.4.1 获取豆瓣分类内容

**接口**：`POST /api/douban/subjects`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | string | 是 | 类型：`movie` 或 `tv` |
| `tag` | string | 否 | 标签/分类 |
| `sort` | string | 否 | 排序：`recommend`/`time`/`rank` |
| `page_limit` | int | 否 | 每页数量（1-50，默认 20） |
| `page_start` | int | 否 | 起始页（最小 0） |

**请求示例**：

```json
{
  "type": "movie",
  "tag": "科幻",
  "sort": "rank",
  "page_limit": 20,
  "page_start": 0
}
```

---

### 2.4.2 获取豆瓣标签列表

**接口**：`POST /api/douban/tags`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `type` | string | 是 | 类型：`movie` 或 `tv` |

**请求示例**：

```json
{
  "type": "movie"
}
```

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `tags` | array | 标签列表 |

---

### 2.4.3 获取图片代理 Token

**接口**：`POST /api/douban/image/token`

**描述**：生成临时 Token 用于图片代理访问

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `token` | string | 临时访问令牌 |
| `expires_in` | int | 有效期（秒，默认 300） |

---

### 2.4.4 图片代理

**接口**：`GET /api/douban/image/proxy`

**认证**：否（使用临时 Token）

**Query 参数**：

| 参数 | 必填 | 说明 |
|------|------|------|
| `token` | 是 | 临时访问令牌 |
| `url` | 是 | 图片 URL |

**限流**：1000 次/分钟

---

## 2.5 用户数据模块 `/api/user/data`

用户数据模块管理用户的搜索历史、播放历史和收藏。

**认证**：全部需要

### 2.5.1 搜索历史

#### 获取搜索历史

**接口**：`POST /api/user/data/search-history/list`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | int | 否 | 限制数量（1-50，默认 20） |

#### 新增搜索记录

**接口**：`POST /api/user/data/search-history/add`

**请求参数**：

| 参数 | 类型 | 必填 | 约束 | 说明 |
|------|------|------|------|------|
| `keyword` | string | 是 | 1-200 字符 | 搜索关键词 |

#### 删除搜索记录

**接口**：`POST /api/user/data/search-history/delete`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 记录 ID |

#### 清空搜索历史

**接口**：`POST /api/user/data/search-history/clear`

---

### 2.5.2 播放历史

#### 获取播放历史

**接口**：`POST /api/user/data/play-history/list`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | int | 否 | 限制数量（1-200，默认 20） |
| `offset` | int | 否 | 偏移量（最小 0） |

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `items` | array | 播放历史列表 |
| `total` | int64 | 总数 |

#### 创建/更新播放历史

**接口**：`POST /api/user/data/play-history/upsert`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `vod_id` | int64 | 是 | 资源 ID |
| `vod_name` | string | 是 | 资源名称 |
| `vod_pic` | string | 是 | 封面图 |
| `resource_domain` | string | 是 | 资源站点域名 |
| `resource_name` | string | 是 | 资源站点名称 |
| `group_key` | string | 是 | 分组 key |
| `source_index` | int | 是 | 播放源索引 |
| `ep_index` | int | 是 | 集索引 |
| `ep_name` | string | 是 | 集名称 |
| `progress` | float | 是 | 播放进度（0-100） |
| `current_time` | float | 是 | 当前时间（秒） |
| `duration` | float | 是 | 总时长（秒） |

#### 更新播放进度

**接口**：`POST /api/user/data/play-history/progress`

**描述**：轻量级进度更新接口，适用于播放中频繁调用

**请求参数**：同 upsert

#### 删除播放历史

**接口**：`POST /api/user/data/play-history/delete`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 记录 ID |

#### 清空播放历史

**接口**：`POST /api/user/data/play-history/clear`

---

### 2.5.3 收藏

#### 获取收藏列表

**接口**：`POST /api/user/data/favorites/list`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | int | 否 | 限制数量（1-200，默认 20） |
| `offset` | int | 否 | 偏移量（最小 0） |
| `keyword` | string | 否 | 搜索关键词 |

#### 添加收藏

**接口**：`POST /api/user/data/favorites/add`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `vod_id` | int64 | 是 | 资源 ID |
| `vod_name` | string | 是 | 资源名称 |
| `vod_pic` | string | 是 | 封面图 |
| `douban_id` | string | 否 | 豆瓣 ID |
| `group_key` | string | 是 | 分组 key |
| `site` | string | 是 | 站点名称 |
| `resource_domain` | string | 是 | 资源站点域名 |
| `resource_name` | string | 是 | 资源站点名称 |

#### 移除收藏

**接口**：`POST /api/user/data/favorites/remove`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `vod_id` | int64 | 是 | 资源 ID |
| `resource_domain` | string | 是 | 资源站点域名 |
| `douban_id` | string | 否 | 豆瓣 ID |

#### 切换收藏状态

**接口**：`POST /api/user/data/favorites/toggle`

**请求参数**：同添加收藏

#### 检查收藏状态

**接口**：`POST /api/user/data/favorites/check`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `vod_id` | int64 | 是 | 资源 ID |
| `resource_domain` | string | 是 | 资源站点域名 |
| `douban_id` | string | 否 | 豆瓣 ID |

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `favorited` | bool | 是否已收藏 |

#### 清空收藏

**接口**：`POST /api/user/data/favorites/clear`

---

## 2.6 下载模块 `/api/download`

下载模块提供下载任务管理、本地文件播放等功能。

**认证**：全部需要

### 2.6.1 创建下载任务

**接口**：`POST /api/download/create`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `vod_id` | int64 | 是 | 资源 ID |
| `vod_name` | string | 是 | 资源名称 |
| `vod_pic` | string | 是 | 封面图 |
| `resource_domain` | string | 是 | 资源站点域名 |
| `resource_name` | string | 是 | 资源站点名称 |
| `group_key` | string | 是 | 分组 key |
| `items` | array | 是 | 下载项列表 |
| `items[].source_index` | int | 是 | 播放源索引 |
| `items[].ep_index` | int | 是 | 集索引 |
| `items[].ep_name` | string | 是 | 集名称 |
| `items[].m3u8_url` | string | 是 | M3U8 地址 |

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `task_ids` | array | 任务 ID 列表 |
| `queued` | int | 入队数量 |
| `skipped` | int | 跳过数量（已存在） |

---

### 2.6.2 获取下载列表

**接口**：`POST /api/download/list`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `status` | int | 否 | 状态筛选 |
| `limit` | int | 否 | 限制数量（1-200，默认 20） |
| `offset` | int | 否 | 偏移量（最小 0） |

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `total` | int64 | 总数 |
| `items` | array | 下载任务列表 |
| `items[].id` | int64 | 任务 ID |
| `items[].vod_id` | int64 | 资源 ID |
| `items[].vod_name` | string | 资源名称 |
| `items[].vod_pic` | string | 封面图 |
| `items[].ep_name` | string | 集名称 |
| `items[].resource_domain` | string | 资源站点域名 |
| `items[].resource_name` | string | 资源站点名称 |
| `items[].status` | int | 状态（0=排队 1=解析 2=下载 3=合并 4=完成 5=失败 6=取消） |
| `items[].progress` | float | 下载进度（0-100） |
| `items[].total_segments` | int | 总分段数 |
| `items[].downloaded_segments` | int | 已下载分段数 |
| `items[].file_size` | int64 | 文件大小（字节） |
| `items[].error_msg` | string | 错误信息 |
| `items[].created_at` | int64 | 创建时间（毫秒时间戳） |
| `items[].updated_at` | int64 | 更新时间（毫秒时间戳） |

**下载状态枚举**：

| 值 | 说明 |
|-----|------|
| 0 | 排队中 |
| 1 | 解析中 |
| 2 | 下载中 |
| 3 | 合并中 |
| 4 | 已完成 |
| 5 | 失败 |
| 6 | 已取消 |

---

### 2.6.3 取消下载

**接口**：`POST /api/download/cancel`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `task_id` | int64 | 是 | 任务 ID |

---

### 2.6.4 删除下载

**接口**：`POST /api/download/delete`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `task_id` | int64 | 是 | 任务 ID |

---

### 2.6.5 重试下载

**接口**：`POST /api/download/retry`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `task_id` | int64 | 是 | 任务 ID |

---

### 2.6.6 检查本地文件

**接口**：`POST /api/download/check`

**描述**：检查资源是否已有本地下载文件

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `resource_domain` | string | 是 | 资源站点域名 |
| `vod_id` | int64 | 是 | 资源 ID |
| `source_index` | int | 是 | 播放源索引 |
| `ep_index` | int | 是 | 集索引 |

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `found` | bool | 是否存在本地文件 |
| `task_id` | int64 | 任务 ID（存在时） |
| `file_url` | string | 播放地址（存在时） |
| `file_format` | string | 文件格式（mp4/ts） |

---

### 2.6.7 获取下载文件

**接口**：`GET /api/download/file/:id`

**描述**：流式播放已下载的文件，支持 HTTP Range 请求

**Path 参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `id` | int64 | 任务 ID |

**响应**：二进制文件流，`Content-Type: video/mp2t` 或 `video/mp4`

**请求示例**：

```
GET /api/download/file/123
Range: bytes=0-1023
```

---

## 2.7 管理模块 `/api/admin`

管理模块提供用户管理、系统配置、用户组管理、资源管理、下载配置等功能。

**认证**：全部需要，且需管理员权限

### 2.7.1 用户管理 `/api/admin/user`

#### 创建用户

**接口**：`POST /api/admin/user/create`

**请求参数**：

| 参数 | 类型 | 必填 | 约束 | 说明 |
|------|------|------|------|------|
| `username` | string | 是 | 3-50 字符，字母数字 | 用户名 |
| `password` | string | 是 | 6-50 字符 | 密码 |
| `nickname` | string | 否 | 最大 50 字符 | 昵称 |
| `role` | int8 | 否 | 0-1 | 角色，默认 0 |

#### 更新用户

**接口**：`POST /api/admin/user/update`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 用户 ID |
| `nickname` | string | 否 | 昵称 |
| `avatar` | string | 否 | 头像 URL |
| `role` | int8 | 否 | 角色 |
| `status` | int8 | 否 | 状态 |
| `group_id` | int64 | 否 | 用户组 ID（null 表示移除） |

#### 重置密码

**接口**：`POST /api/admin/user/reset-password`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 用户 ID |
| `new_password` | string | 是 | 新密码（6-50 字符） |

#### 用户列表

**接口**：`POST /api/admin/user/list`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 是 | 页码（最小 1） |
| `size` | int | 否 | 每页数量（1-100） |
| `keyword` | string | 否 | 搜索关键词 |
| `role` | int8 | 否 | 角色筛选 |
| `status` | int8 | 否 | 状态筛选 |

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `items` | array | 用户列表 |
| `total` | int64 | 总数 |
| `page` | int | 当前页 |
| `size` | int | 每页数量 |
| `total_pages` | int | 总页数 |

#### 删除用户

**接口**：`POST /api/admin/user/delete`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 用户 ID |

#### 踢用户下线

**接口**：`POST /api/admin/user/kick`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `user_id` | int64 | 是 | 用户 ID |
| `device_type` | int8 | 否 | 设备类型（指定则踢除该类型设备） |

---

### 2.7.2 系统配置 `/api/admin/config`

#### 配置列表

**接口**：`POST /api/admin/config/list`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `group` | string | 否 | 配置分组 |

#### 创建配置

**接口**：`POST /api/admin/config/create`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `config_key` | string | 是 | 配置键 |
| `config_group` | string | 是 | 配置分组 |
| `title` | string | 否 | 标题 |
| `title1-6` | string | 否 | 副标题 |
| `value1-6` | string | 否 | 配置值 |
| `sort_order` | int | 否 | 排序 |
| `is_enabled` | bool | 否 | 是否启用 |
| `remark` | string | 否 | 备注 |

#### 更新配置

**接口**：`POST /api/admin/config/update`

**请求参数**：同创建，通过 `config_key` 标识

#### 删除配置

**接口**：`POST /api/admin/config/delete`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 配置 ID |

#### 刷新配置缓存

**接口**：`POST /api/admin/config/refresh-cache`

---

### 2.7.3 用户组管理 `/api/admin/group`

#### 创建用户组

**接口**：`POST /api/admin/group/create`

**请求参数**：

| 参数 | 类型 | 必填 | 约束 | 说明 |
|------|------|------|------|------|
| `name` | string | 是 | 1-50 字符 | 用户组名称 |
| `remark` | string | 否 | 最大 256 字符 | 备注 |

#### 更新用户组

**接口**：`POST /api/admin/group/update`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 用户组 ID |
| `name` | string | 否 | 用户组名称 |
| `remark` | string | 否 | 备注 |

#### 删除用户组

**接口**：`POST /api/admin/group/delete`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 用户组 ID |

#### 用户组列表

**接口**：`POST /api/admin/group/list`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `page` | int | 是 | 页码（最小 1） |
| `size` | int | 否 | 每页数量（1-100） |
| `keyword` | string | 否 | 搜索关键词 |

#### 用户组详情

**接口**：`POST /api/admin/group/detail`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | int64 | 是 | 用户组 ID |

#### 设置用户组资源

**接口**：`POST /api/admin/group/set-resources`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `group_id` | int64 | 是 | 用户组 ID |
| `config_keys` | array | 否 | 配置键列表（最多 200 项） |

#### 设置用户所属组

**接口**：`POST /api/admin/group/set-user`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `user_id` | int64 | 是 | 用户 ID |
| `group_id` | int64 | 否 | 用户组 ID（null 表示移除） |

---

### 2.7.4 资源管理 `/api/admin/resource`

#### 获取订阅配置

**接口**：`POST /api/admin/resource/subscribe/config`

#### 更新订阅配置

**接口**：`POST /api/admin/resource/subscribe/update`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `subscribe_url` | string | 是 | 订阅 URL |
| `auto_subscribe` | bool | 否 | 是否自动订阅 |
| `cron_expr` | string | 否 | Cron 表达式 |

#### 手动拉取订阅

**接口**：`POST /api/admin/resource/subscribe/fetch`

#### 测试代理连接

**接口**：`POST /api/admin/resource/proxy/test`

---

### 2.7.5 下载管理 `/api/admin/download`

#### 管理员获取所有下载

**接口**：`POST /api/admin/download/list`

**请求参数**：同用户端下载列表

#### 获取下载配置

**接口**：`POST /api/admin/download/config`

**响应参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `download_dir` | string | 下载目录 |
| `max_concurrent` | int | 最大并发任务数 |
| `segment_concurrency` | int | 分段并发数 |

#### 更新下载配置

**接口**：`POST /api/admin/download/config/update`

**请求参数**：

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `download_dir` | string | 否 | 下载目录 |
| `max_concurrent` | int | 否 | 最大并发任务数（1-10） |
| `segment_concurrency` | int | 否 | 分段并发数（1-50） |

---

## 3. 业务流程规范

### 3.1 登录流程

```
┌─────────────┐
│  LoginPage  │
└──────┬──────┘
       │
       ▼
┌──────────────────────┐
│ POST /api/auth/login │
│ {username, password, │
│  device_type}        │
└──────────┬───────────┘
           │
           ▼
    ┌─────────────┐
    │ 登录成功？   │
    └──────┬──────┘
           │
     ┌─────┴─────┐
     │是          │否
     ▼            ▼
┌─────────┐  ┌─────────────┐
│ 存储    │  │ 显示错误信息 │
│ Token   │  └─────────────┘
└────┬────┘
     │
     ▼
┌─────────────────┐
│  跳转首页        │
└─────────────────┘
```

#### Token 自动刷新机制

```
请求携带 access_token
       │
       ▼
┌─────────────────┐     ┌─────────────────┐
│  响应 401？      │─否─▶│  继续正常处理    │
└────────┬────────┘     └─────────────────┘
         │是
         ▼
┌─────────────────┐
│ 调用 /api/auth/ │
│ refresh 刷新    │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  刷新成功？      │
└────────┬────────┘
         │
   ┌─────┴─────┐
   │是          │否
   ▼            ▼
┌────────┐  ┌─────────┐
│ 存储新  │  │ 跳转    │
│ Token   │  │ 登录页  │
└────┬───┘  └─────────┘
     │
     ▼
┌─────────────────┐
│ 重试原请求      │
└─────────────────┘
```

---

### 3.2 首页内容加载流程

```
┌─────────────┐
│   HomePage  │
└──────┬──────┘
       │
       ├─────────────────────────────────┐
       │                                 │
       ▼                                 ▼
┌───────────────────┐           ┌───────────────────┐
│ POST /api/douban/ │           │ POST /api/douban/ │
│ tags (type=movie) │           │ tags (type=tv)    │
└─────────┬─────────┘           └─────────┬─────────┘
         │                               │
         └───────────┬───────────────────┘
                     ▼
         ┌───────────────────────┐
         │ POST /api/douban/     │
         │ image/token           │
         └─────────┬─────────────┘
                   │
                   ▼
         ┌───────────────────────┐
         │ POST /api/douban/     │
         │ subjects (并行请求)   │
         │ - hero (Banner)       │
         │ - movie (电影列表)    │
         │ - tv (剧集列表)       │
         └─────────┬─────────────┘
                   │
                   ▼
         ┌───────────────────────┐
         │  渲染首页 UI          │
         │  - Banner 轮播图       │
         │  - 电影分类列表        │
         │  - 剧集分类列表        │
         └───────────────────────┘
```

---

### 3.3 聚合搜索流程（SSE）

```
┌─────────────┐
│  SearchPage │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ POST /api/resource/sites│
│ 获取可用资源站点        │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 用户输入关键词          │
│ 点击搜索                │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ POST /api/resource/search│
│ {q, douban_id?,         │
│  resources?}            │
│                         │
│ 使用 EventSource 接收    │
└──────────┬──────────────┘
           │
           ▼
    ┌──────────────┐
    │ SSE 事件循环  │
    └───────┬──────┘
            │
    ┌───────┼───────┐
    ▼       ▼       ▼
┌───────┐ ┌─────┐ ┌──────┐
│result │ │done │ │error │
│事件   │ │事件  │ │事件  │
└───┬───┘ └──┬──┘ └───┬──┘
    │         │        │
    ▼         │        ▼
┌─────────┐   │   ┌─────────┐
│ 追加结果 │   │   │ 显示错误 │
│ 到列表   │   │   │ 提示    │
└─────────┘   │   └─────────┘
              │
              ▼
        ┌───────────┐
        │ 更新统计  │
        │ 显示完成  │
        └───────────┘
```

#### SSE 中断处理

```typescript
// 搜索组件可主动中断
const searchController = new AbortController();

eventSource.addEventListener('result', (e) => {
  // 处理结果
});

eventSource.addEventListener('done', (e) => {
  // 搜索完成
  eventSource.close();
});

// 主动中断
searchController.abort();
```

---

### 3.4 视频播放流程

```
┌─────────────┐
│  DetailPage │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ POST /api/resource/    │
│ detail                  │
│ {site, vod_id}          │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 显示播放源列表          │
│ 用户选择播放源和剧集    │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 跳转 PlayPage           │
│ 同时传入资源信息        │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ POST /api/download/check│
│ 检查本地是否有下载文件   │
└──────────┬──────────────┘
           │
     ┌─────┴─────┐
     │有本地文件？ │
     └─────┬─────┘
      ┌────┴────┐
      │是        │否
      ▼          ▼
┌───────────┐ ┌───────────────────┐
│使用本地文件│ │使用 /api/resource │
│播放        │ │detail 获取播放URL │
│GET /api/  │ │播放                │
│download/  │ │                   │
│file/:id   │ │                   │
└─────┬─────┘ └───────────────────┘
      │
      └──────────────┐
                     │
                     ▼
          ┌───────────────────┐
          │ 播放时定时调用     │
          │ POST /api/user/   │
          │ data/play-history/│
          │ progress          │
          │ 更新播放进度       │
          └───────────────────┘
```

---

### 3.5 下载任务流程

```
┌─────────────┐
│  DetailPage │
│  PlayPage   │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ POST /api/download/    │
│ create                  │
│ {vod_id, vod_name,      │
│  items[]}              │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 获取 task_ids           │
│ 跳转到 DownloadPage     │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ POST /api/download/list │
│ 轮询获取下载状态        │
│ 间隔 3 秒               │
└──────────┬──────────────┘
           │
           ▼
    ┌──────────────┐
    │ 下载完成？    │
    └──────┬───────┘
           │
     ┌─────┴─────┐
     │是          │否
     ▼            ▼
┌─────────┐  ┌───────────────────┐
│ 可播放  │  │ 显示下载进度      │
│         │  │ /失败原因         │
└─────────┘  └───────────────────┘

┌─────────────────────────┐
│ 用户操作                 │
│ - cancel (取消下载)      │
│ - delete (删除任务)     │
│ - retry (重试失败)      │
└─────────────────────────┘
```

---

### 3.6 收藏/历史记录流程

```
┌─────────────────────────────────────────────────┐
│                   全局页面                        │
├─────────────────────────────────────────────────┤
│                                                  │
│  用户点击收藏按钮                                │
│         │                                        │
│         ▼                                        │
│  ┌─────────────────────┐                        │
│  │ POST /api/user/data │                        │
│  │ /favorites/toggle   │                        │
│  │ {vod_id, ...}        │                        │
│  └──────────┬──────────┘                        │
│             │                                    │
│     ┌───────┴───────┐                           │
│     │favorited=true │favorited=false            │
│     ▼               ▼                           │
│  ┌────────┐   ┌───────────┐                    │
│  │ 调用   │   │ 调用      │                    │
│  │ add    │   │ remove    │                    │
│  └────────┘   └───────────┘                    │
│             │                                    │
│             ▼                                    │
│  ┌─────────────────────┐                        │
│  │ 更新本地 UI 状态    │                        │
│  └─────────────────────┘                        │
│                                                  │
│  播放视频时自动记录                              │
│         │                                        │
│         ▼                                        │
│  ┌─────────────────────┐                        │
│  │ POST /api/user/data │                        │
│  │ /play-history/upsert│                        │
│  └─────────────────────┘                        │
│                                                  │
└─────────────────────────────────────────────────┘

┌─────────────┐
│ FavoritePage│
│ HistoryPage │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ POST /api/user/data/    │
│ /favorites/list 或      │
│ /play-history/list      │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│ 渲染列表，支持          │
│ - 删除单条记录           │
│ - 清空全部               │
└─────────────────────────┘
```

---

## 4. 附录

### 4.1 错误码表

| code | 说明 | 处理建议 |
|------|------|----------|
| 200 | 成功 | - |
| 400 | 请求参数错误 | 检查请求参数格式和约束 |
| 401 | 未授权 | Token 无效或过期，需重新登录 |
| 403 | 权限不足 | 检查用户角色是否有权限 |
| 404 | 资源不存在 | 检查请求的资源 ID 是否正确 |
| 500 | 服务器内部错误 | 联系管理员或重试 |

### 4.2 分页规范

列表查询接口统一使用分页参数：

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `page` | int | 是 | 1 | 页码（最小 1） |
| `size` | int | 否 | 20 | 每页数量（1-100） |

响应包含分页元数据：

| 字段 | 类型 | 说明 |
|------|------|------|
| `items` | array | 数据列表 |
| `total` | int64 | 总记录数 |
| `page` | int | 当前页 |
| `page_size` | int | 每页数量 |
| `total_pages` | int | 总页数 |

### 4.3 图片代理使用规范

#### 豆瓣图片

1. 调用 `/api/douban/image/token` 获取临时 Token（有效期 5 分钟）
2. 使用 Token 构建图片代理 URL：`/api/douban/image/proxy?token={token}&url={encoded_url}`
3. Token 建议提前 30 秒刷新，避免过期

#### 资源图片

直接使用：`/api/resource/image/proxy?url={encoded_url}`

### 4.4 SSE 流式接口规范

搜索接口使用 Server-Sent Events，返回流式数据：

```
event: result
data: {...}

event: done
data: {...}
```

前端使用 `EventSource` 或 `fetch` + `ReadableStream` 接收。

客户端应支持：
- 中断连接（主动 `close()` 或 `abort()`）
- 重连机制（可选）
- 错误处理

### 4.5 HTTP Range 请求

下载文件播放接口支持 HTTP Range 请求，用于视频拖动和分段加载。

**请求**：
```
GET /api/download/file/:id
Range: bytes=0-1023
```

**响应**（206 Partial Content）：
```
HTTP/1.1 206 Partial Content
Content-Range: bytes 0-1023/{total_size}
Content-Length: 1024
Content-Type: video/mp4
```

---

## 5. 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v1.0.0 | 2026-06-22 | 初始版本，包含所有接口和流程规范 |
