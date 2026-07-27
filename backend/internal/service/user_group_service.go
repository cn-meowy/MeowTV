package service

import (
	"context"
	"encoding/json"
	"log/slog"

	"cn.meow/meowtv/internal/cache"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

// UserGroupService 用户组业务层
type UserGroupService struct {
	groupRepo repository.UserGroupRepository
	userRepo  repository.UserRepository
	cache     cache.Cache
}

// NewUserGroupService 创建用户组 Service
func NewUserGroupService(groupRepo repository.UserGroupRepository, userRepo repository.UserRepository, cache cache.Cache) *UserGroupService {
	return &UserGroupService{
		groupRepo: groupRepo,
		userRepo:  userRepo,
		cache:     cache,
	}
}

// CreateGroup 创建用户组
func (s *UserGroupService) CreateGroup(ctx context.Context, req *request.CreateGroupReq) (*response.GroupResp, error) {
	// 检查名称是否重复（包含软删除记录，避免唯一索引冲突）
	existing, err := s.groupRepo.GetByNameUnscoped(ctx, req.Name)
	if err == nil && existing != nil {
		if existing.DeletedAt.Valid {
			// 软删除记录存在，Create 内部会自动恢复，直接调用 Create
		} else {
			// 未删除记录已存在，返回冲突错误
			return nil, errs.WithMsg("用户组名称已存在", errs.ErrConflict)
		}
	}

	group := &entity.UserGroup{
		Name:   req.Name,
		Remark: req.Remark,
	}
	if err := s.groupRepo.Create(ctx, group); err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	return &response.GroupResp{
		ID:            group.ID,
		Name:          group.Name,
		Remark:        group.Remark,
		ConfigKeys:    []string{},
		ResourceCount: 0,
		UserCount:     0,
		CreatedAt:     group.CreatedAt.Format("2006-01-02 15:04:05"),
		UpdatedAt:     group.UpdatedAt.Format("2006-01-02 15:04:05"),
	}, nil
}

// UpdateGroup 更新用户组
func (s *UserGroupService) UpdateGroup(ctx context.Context, req *request.UpdateGroupReq) error {
	_, err := s.groupRepo.GetByID(ctx, req.ID)
	if err != nil {
		return errs.WithMsg("用户组不存在", errs.ErrNotFound)
	}

	fields := make(map[string]interface{})
	if req.Name != nil {
		// 检查名称是否与其他组重复（包含软删除记录，避免唯一索引冲突）
		existing, err := s.groupRepo.GetByNameUnscoped(ctx, *req.Name)
		if err == nil && existing != nil && existing.ID != req.ID {
			if existing.DeletedAt.Valid {
				// 同名记录已软删除，更新会因唯一索引冲突失败
				return errs.WithMsg("该名称已被已删除的用户组占用，请联系管理员", errs.ErrConflict)
			}
			return errs.WithMsg("用户组名称已存在", errs.ErrConflict)
		}
		fields["name"] = *req.Name
	}
	if req.Remark != nil {
		fields["remark"] = *req.Remark
	}

	if len(fields) == 0 {
		return nil
	}

	if err := s.groupRepo.Update(ctx, req.ID, fields); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	return nil
}

// DeleteGroup 删除用户组
func (s *UserGroupService) DeleteGroup(ctx context.Context, req *request.DeleteGroupReq) error {
	_, err := s.groupRepo.GetByID(ctx, req.ID)
	if err != nil {
		return errs.WithMsg("用户组不存在", errs.ErrNotFound)
	}

	// 检查是否有用户关联此组
	userCount, err := s.groupRepo.CountUsersByGroupID(ctx, req.ID)
	if err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}
	if userCount > 0 {
		return errs.WithMsg("该用户组下还有用户，请先移除用户后再删除", errs.ErrBadRequest)
	}

	// 删除关联资源
	if err := s.groupRepo.DeleteResourcesByGroupID(ctx, req.ID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 删除用户组（软删除）
	if err := s.groupRepo.Delete(ctx, req.ID); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 清除缓存
	s.clearGroupCache(ctx, req.ID)

	return nil
}

// ListGroups 用户组列表
func (s *UserGroupService) ListGroups(ctx context.Context, req *request.GroupListReq) (*response.Paginated, error) {
	if req.Page <= 0 {
		req.Page = 1
	}
	if req.Size <= 0 {
		req.Size = 20
	}
	groups, total, err := s.groupRepo.List(ctx, req)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	items := make([]*response.GroupListItem, 0, len(groups))
	for _, g := range groups {
		resourceCount, _ := s.getResourceCount(ctx, g.ID)
		userCount, _ := s.groupRepo.CountUsersByGroupID(ctx, g.ID)
		items = append(items, &response.GroupListItem{
			ID:            g.ID,
			Name:          g.Name,
			Remark:        g.Remark,
			ResourceCount: resourceCount,
			UserCount:     int(userCount),
			CreatedAt:     g.CreatedAt,
		})
	}

	return response.NewPaginated(items, total, req.Page, req.Size), nil
}

// GetGroupDetail 用户组详情（含关联资源列表）
func (s *UserGroupService) GetGroupDetail(ctx context.Context, id int64) (*response.GroupResp, error) {
	group, err := s.groupRepo.GetByID(ctx, id)
	if err != nil {
		return nil, errs.WithMsg("用户组不存在", errs.ErrNotFound)
	}

	configKeys, err := s.GetGroupResources(ctx, id)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	userCount, _ := s.groupRepo.CountUsersByGroupID(ctx, id)

	return &response.GroupResp{
		ID:            group.ID,
		Name:          group.Name,
		Remark:        group.Remark,
		ConfigKeys:    configKeys,
		ResourceCount: len(configKeys),
		UserCount:     int(userCount),
		CreatedAt:     group.CreatedAt.Format("2006-01-02 15:04:05"),
		UpdatedAt:     group.UpdatedAt.Format("2006-01-02 15:04:05"),
	}, nil
}

// SetGroupResources 设置用户组关联资源站点
func (s *UserGroupService) SetGroupResources(ctx context.Context, req *request.SetGroupResourcesReq) error {
	// 检查用户组是否存在
	_, err := s.groupRepo.GetByID(ctx, req.GroupID)
	if err != nil {
		return errs.WithMsg("用户组不存在", errs.ErrNotFound)
	}

	// 去重 configKeys
	seen := make(map[string]bool)
	uniqueKeys := make([]string, 0, len(req.ConfigKeys))
	for _, key := range req.ConfigKeys {
		if !seen[key] && key != "" {
			seen[key] = true
			uniqueKeys = append(uniqueKeys, key)
		}
	}

	if err := s.groupRepo.SetResources(ctx, req.GroupID, uniqueKeys); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 清除缓存
	s.clearGroupCache(ctx, req.GroupID)

	return nil
}

// GetGroupResources 获取用户组关联的 config_key 列表（带缓存）
func (s *UserGroupService) GetGroupResources(ctx context.Context, groupID int64) ([]string, error) {
	ck := cache.KeyUserGroupResources(groupID)
	val, err := s.cache.Get(ctx, ck.Key)
	if err == nil && val != "" {
		var keys []string
		if json.Unmarshal([]byte(val), &keys) == nil {
			return keys, nil
		}
	}

	// 查库
	records, err := s.groupRepo.GetResourcesByGroupID(ctx, groupID)
	if err != nil {
		return nil, err
	}

	keys := make([]string, 0, len(records))
	for _, r := range records {
		keys = append(keys, r.ConfigKey)
	}

	// 写入缓存
	if data, e := json.Marshal(keys); e == nil {
		_ = s.cache.Set(ctx, ck.Key, string(data), ck.TTL)
	}

	return keys, nil
}

// SetUserGroup 设置用户所属用户组
func (s *UserGroupService) SetUserGroup(ctx context.Context, req *request.SetUserGroupReq) error {
	// 检查用户是否存在
	user, err := s.userRepo.GetByID(ctx, req.UserID)
	if err != nil {
		return errs.WithMsg("用户不存在", errs.ErrNotFound)
	}

	// 如果指定了 group_id，检查用户组是否存在
	if req.GroupID != nil && *req.GroupID > 0 {
		_, err := s.groupRepo.GetByID(ctx, *req.GroupID)
		if err != nil {
			return errs.WithMsg("用户组不存在", errs.ErrNotFound)
		}
	}

	// 更新用户的 group_id
	if err := s.userRepo.Update(ctx, req.UserID, map[string]interface{}{
		"group_id": req.GroupID,
	}); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 清除用户 group_id 缓存
	s.ClearUserGroupIDCache(ctx, req.UserID)

	_ = user
	return nil
}

// GetUserGroupID 获取用户的 group_id（带缓存）
func (s *UserGroupService) GetUserGroupID(ctx context.Context, userID int64) (*int64, error) {
	ck := cache.KeyUserGroupID(userID)
	val, err := s.cache.Get(ctx, ck.Key)
	if err == nil && val != "" {
		if val == "null" {
			return nil, nil
		}
		var groupID int64
		if json.Unmarshal([]byte(val), &groupID) == nil {
			return &groupID, nil
		}
	}

	// 查用户表
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, err
	}

	// 写入缓存
	s.CacheUserGroupID(ctx, userID, user.GroupID)

	return user.GroupID, nil
}

// GetGroupName 获取用户组名称
func (s *UserGroupService) GetGroupName(ctx context.Context, groupID int64) string {
	group, err := s.groupRepo.GetByID(ctx, groupID)
	if err != nil {
		return ""
	}
	return group.Name
}

// getResourceCount 获取用户组关联资源数量
func (s *UserGroupService) getResourceCount(ctx context.Context, groupID int64) (int, error) {
	records, err := s.groupRepo.GetResourcesByGroupID(ctx, groupID)
	if err != nil {
		return 0, err
	}
	return len(records), nil
}

// clearGroupCache 清除用户组相关缓存
func (s *UserGroupService) clearGroupCache(ctx context.Context, groupID int64) {
	ck := cache.KeyUserGroupResources(groupID)
	if err := s.cache.Delete(ctx, ck.Key); err != nil {
		slog.Error("failed to clear group resources cache", "group_id", groupID, "error", err)
	}
}

// ClearUserGroupIDCache 清除用户 group_id 缓存
func (s *UserGroupService) ClearUserGroupIDCache(ctx context.Context, userID int64) {
	ck := cache.KeyUserGroupID(userID)
	if err := s.cache.Delete(ctx, ck.Key); err != nil {
		slog.Error("failed to clear user group_id cache", "user_id", userID, "error", err)
	}
}

// CacheUserGroupID 缓存用户的 group_id
func (s *UserGroupService) CacheUserGroupID(ctx context.Context, userID int64, groupID *int64) {
	ck := cache.KeyUserGroupID(userID)
	var data []byte
	if groupID == nil {
		data = []byte("null")
	} else {
		data, _ = json.Marshal(*groupID)
	}
	_ = s.cache.Set(ctx, ck.Key, string(data), ck.TTL)
}
