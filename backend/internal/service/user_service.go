package service

import (
	"context"

	"golang.org/x/crypto/bcrypt"

	"cn.meow/meowtv/internal/auth"
	"cn.meow/meowtv/internal/errs"
	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/dto/response"
	"cn.meow/meowtv/internal/model/entity"
	"cn.meow/meowtv/internal/repository"
)

// UserService 用户业务层
type UserService struct {
	userRepo     repository.UserRepository
	blacklist    *auth.BlacklistManager
	groupService *UserGroupService
}

// NewUserService 创建用户 Service
func NewUserService(
	userRepo repository.UserRepository,
	blacklist *auth.BlacklistManager,
	groupService *UserGroupService,
) *UserService {
	return &UserService{
		userRepo:     userRepo,
		blacklist:    blacklist,
		groupService: groupService,
	}
}

// GetProfile 获取用户信息
func (s *UserService) GetProfile(ctx context.Context, userID int64) (*response.ProfileResp, error) {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return nil, errs.WithMsg("用户不存在", errs.ErrNotFound)
	}

	resp := &response.ProfileResp{
		ID:       user.ID,
		Username: user.Username,
		Nickname: user.Nickname,
		Avatar:   user.Avatar,
		Role:     int8(user.Role),
		Status:   int8(user.Status),
		GroupID:  user.GroupID,
	}

	// 填充用户组名称
	if user.GroupID != nil && *user.GroupID > 0 && s.groupService != nil {
		resp.GroupName = s.groupService.GetGroupName(ctx, *user.GroupID)
	}

	return resp, nil
}

// UpdateProfile 修改个人信息
func (s *UserService) UpdateProfile(ctx context.Context, userID int64, req *request.UpdateProfileReq) error {
	fields := make(map[string]interface{})
	if req.Nickname != nil {
		fields["nickname"] = *req.Nickname
	}
	if req.Avatar != nil {
		fields["avatar"] = *req.Avatar
	}
	if len(fields) == 0 {
		return nil
	}
	return s.userRepo.Update(ctx, userID, fields)
}

// ChangePassword 修改密码
func (s *UserService) ChangePassword(ctx context.Context, userID int64, req *request.ChangePasswordReq) error {
	user, err := s.userRepo.GetByID(ctx, userID)
	if err != nil {
		return errs.WithMsg("用户不存在", errs.ErrNotFound)
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.OldPassword)); err != nil {
		return errs.WithMsg("旧密码不正确", errs.ErrUnauthorized)
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	if err := s.userRepo.UpdatePassword(ctx, userID, string(hash)); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 修改密码后踢掉所有设备
	_ = s.blacklist.KickByDeviceType(ctx, userID, nil)

	return nil
}

// GetDevices 查看在线设备
func (s *UserService) GetDevices(ctx context.Context, userID int64) (*response.DeviceListResp, error) {
	entries, err := s.blacklist.GetUserDevices(ctx, userID)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	devices := make([]response.DeviceInfo, 0, len(entries))
	for _, entry := range entries {
		devices = append(devices, response.DeviceInfo{
			DeviceID:     entry.DeviceID,
			DeviceName:   entry.DeviceName,
			DeviceType:   entry.DeviceType,
			LastActiveAt: entry.LastActiveAt,
			Online:       entry.Online,
		})
	}

	return &response.DeviceListResp{Devices: devices}, nil
}

// KickDevice 踢掉指定设备
func (s *UserService) KickDevice(ctx context.Context, userID int64, deviceType int8) error {
	return s.blacklist.KickByDeviceType(ctx, userID, &deviceType)
}

// CreateUser 管理员创建用户
func (s *UserService) CreateUser(ctx context.Context, req *request.CreateUserReq) (*response.CreateUserResp, error) {
	// 检查用户名是否已存在
	existing, _ := s.userRepo.GetByUsername(ctx, req.Username)
	if existing != nil {
		return nil, errs.WithMsg("用户名已存在", errs.ErrConflict)
	}

	// 如果指定了 group_id，先校验用户组存在
	if req.GroupID != nil && *req.GroupID > 0 && s.groupService != nil {
		if _, err := s.groupService.GetGroupByID(ctx, *req.GroupID); err != nil {
			return nil, errs.WithMsg("用户组不存在", errs.ErrNotFound)
		}
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	nickname := req.Nickname
	if nickname == "" {
		nickname = req.Username
	}

	role := entity.RoleUser
	if req.Role != nil {
		role = entity.Role(*req.Role)
	}

	user := &entity.User{
		Username:     req.Username,
		PasswordHash: string(hash),
		Nickname:     nickname,
		Role:         role,
		Status:       entity.StatusEnabled,
		GroupID:      req.GroupID,
	}

	if err := s.userRepo.Create(ctx, user); err != nil {
		return nil, errs.Wrap(err, errs.ErrInternal)
	}

	// 主动清除 group_id 缓存，防止热启动场景下缓存了旧值
	if s.groupService != nil {
		s.groupService.ClearUserGroupIDCache(ctx, user.ID)
	}

	return &response.CreateUserResp{
		ID:       user.ID,
		Username: user.Username,
		Nickname: user.Nickname,
		Role:     int8(user.Role),
	}, nil
}

// UpdateUser 管理员编辑用户
func (s *UserService) UpdateUser(ctx context.Context, req *request.UpdateUserReq) error {
	fields := make(map[string]interface{})
	if req.Nickname != nil {
		fields["nickname"] = *req.Nickname
	}
	if req.Avatar != nil {
		fields["avatar"] = *req.Avatar
	}
	if req.Role != nil {
		fields["role"] = *req.Role
	}
	if req.Status != nil {
		fields["status"] = *req.Status
	}
	if req.GroupID != nil {
		fields["group_id"] = *req.GroupID
	}
	if len(fields) == 0 {
		return nil
	}

	if err := s.userRepo.Update(ctx, req.ID, fields); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 禁用用户时踢掉所有设备
	if req.Status != nil && *req.Status == int8(entity.StatusDisabled) {
		_ = s.blacklist.KickByDeviceType(ctx, req.ID, nil)
	}

	return nil
}

// ResetPassword 管理员重置密码
func (s *UserService) ResetPassword(ctx context.Context, req *request.ResetPasswordReq) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(req.NewPassword), bcrypt.DefaultCost)
	if err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	if err := s.userRepo.UpdatePassword(ctx, req.ID, string(hash)); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 重置密码后踢掉所有设备
	_ = s.blacklist.KickByDeviceType(ctx, req.ID, nil)

	return nil
}

// UserList 用户列表
func (s *UserService) UserList(ctx context.Context, req *request.UserListReq) ([]response.UserListItem, int64, error) {
	users, total, err := s.userRepo.List(ctx, req)
	if err != nil {
		return nil, 0, errs.Wrap(err, errs.ErrInternal)
	}

	items := make([]response.UserListItem, 0, len(users))
	for _, u := range users {
		var lastLoginAt *string
		if u.LastLoginAt != nil {
			t := u.LastLoginAt.Format("2006-01-02 15:04:05")
			lastLoginAt = &t
		}
		items = append(items, response.UserListItem{
			ID:          u.ID,
			Username:    u.Username,
			Nickname:    u.Nickname,
			Avatar:      u.Avatar,
			Role:        int8(u.Role),
			Status:      int8(u.Status),
			GroupID:     u.GroupID,
			LastLoginAt: lastLoginAt,
			CreatedAt:   u.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	return items, total, nil
}

// DeleteUser 管理员删除用户
func (s *UserService) DeleteUser(ctx context.Context, id int64) error {
	if err := s.userRepo.Delete(ctx, id); err != nil {
		return errs.Wrap(err, errs.ErrInternal)
	}

	// 踢掉所有设备
	_ = s.blacklist.KickByDeviceType(ctx, id, nil)

	return nil
}

// KickUser 管理员踢用户下线
func (s *UserService) KickUser(ctx context.Context, req *request.KickUserReq) error {
	return s.blacklist.KickByDeviceType(ctx, req.UserID, req.DeviceType)
}
