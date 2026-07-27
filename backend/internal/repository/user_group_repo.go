package repository

import (
	"context"
	"errors"

	"gorm.io/gorm"

	"cn.meow/meowtv/internal/model/dto/request"
	"cn.meow/meowtv/internal/model/entity"
)

// UserGroupRepository 用户组数据层接口
type UserGroupRepository interface {
	// 用户组 CRUD
	Create(ctx context.Context, group *entity.UserGroup) error
	GetByID(ctx context.Context, id int64) (*entity.UserGroup, error)
	GetByName(ctx context.Context, name string) (*entity.UserGroup, error)
	// GetByNameUnscoped 查找用户组（包含软删除记录），用于创建时检查唯一约束
	GetByNameUnscoped(ctx context.Context, name string) (*entity.UserGroup, error)
	Update(ctx context.Context, id int64, fields map[string]interface{}) error
	Delete(ctx context.Context, id int64) error
	List(ctx context.Context, req *request.GroupListReq) ([]*entity.UserGroup, int64, error)

	// 用户组资源关联
	GetResourcesByGroupID(ctx context.Context, groupID int64) ([]*entity.UserGroupResource, error)
	SetResources(ctx context.Context, groupID int64, configKeys []string) error
	DeleteResourcesByGroupID(ctx context.Context, groupID int64) error

	// 统计
	CountUsersByGroupID(ctx context.Context, groupID int64) (int64, error)
}

// userGroupRepository GORM 实现
type userGroupRepository struct {
	db *gorm.DB
}

// NewUserGroupRepository 创建用户组 Repository
func NewUserGroupRepository(db *gorm.DB) UserGroupRepository {
	return &userGroupRepository{db: db}
}

func (r *userGroupRepository) Create(ctx context.Context, group *entity.UserGroup) error {
	// 使用 Unscoped 检查是否存在同名记录（包括软删除），避免唯一索引冲突
	var existing entity.UserGroup
	result := r.db.WithContext(ctx).Unscoped().Where("name = ?", group.Name).First(&existing)

	if result.Error == nil {
		// 找到同名记录
		if existing.DeletedAt.Valid {
			// 软删除记录存在，恢复并更新字段
			existing.Remark = group.Remark
			existing.DeletedAt = gorm.DeletedAt{} // 清除软删除状态
			return r.db.WithContext(ctx).Unscoped().Save(&existing).Error
		}
		// 未删除记录已存在，返回错误
		return errors.New("用户组名称已存在")
	}

	if result.Error != gorm.ErrRecordNotFound {
		return result.Error
	}

	// 不存在同名记录，直接创建
	return r.db.WithContext(ctx).Create(group).Error
}

func (r *userGroupRepository) GetByID(ctx context.Context, id int64) (*entity.UserGroup, error) {
	var group entity.UserGroup
	if err := r.db.WithContext(ctx).First(&group, id).Error; err != nil {
		return nil, err
	}
	return &group, nil
}

func (r *userGroupRepository) GetByName(ctx context.Context, name string) (*entity.UserGroup, error) {
	var group entity.UserGroup
	if err := r.db.WithContext(ctx).Where("name = ?", name).First(&group).Error; err != nil {
		return nil, err
	}
	return &group, nil
}

// GetByNameUnscoped 查找用户组（包含软删除记录），用于创建时检查唯一约束
func (r *userGroupRepository) GetByNameUnscoped(ctx context.Context, name string) (*entity.UserGroup, error) {
	var group entity.UserGroup
	if err := r.db.WithContext(ctx).Unscoped().Where("name = ?", name).First(&group).Error; err != nil {
		return nil, err
	}
	return &group, nil
}

func (r *userGroupRepository) Update(ctx context.Context, id int64, fields map[string]interface{}) error {
	return r.db.WithContext(ctx).Model(&entity.UserGroup{}).Where("id = ?", id).Updates(fields).Error
}

func (r *userGroupRepository) Delete(ctx context.Context, id int64) error {
	return r.db.WithContext(ctx).Delete(&entity.UserGroup{}, id).Error
}

func (r *userGroupRepository) List(ctx context.Context, req *request.GroupListReq) ([]*entity.UserGroup, int64, error) {
	var groups []*entity.UserGroup
	var total int64

	query := r.db.WithContext(ctx).Model(&entity.UserGroup{})

	// 关键字模糊搜索
	if req.Keyword != "" {
		query = query.Where("name LIKE ?", "%"+req.Keyword+"%")
	}

	// 计算总数
	if err := query.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	// 分页查询
	offset := (req.Page - 1) * req.Size
	if err := query.Order("id DESC").Offset(offset).Limit(req.Size).Find(&groups).Error; err != nil {
		return nil, 0, err
	}

	return groups, total, nil
}

func (r *userGroupRepository) GetResourcesByGroupID(ctx context.Context, groupID int64) ([]*entity.UserGroupResource, error) {
	var list []*entity.UserGroupResource
	if err := r.db.WithContext(ctx).Where("group_id = ?", groupID).Find(&list).Error; err != nil {
		return nil, err
	}
	return list, nil
}

func (r *userGroupRepository) SetResources(ctx context.Context, groupID int64, configKeys []string) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. 删除旧记录
		if err := tx.Where("group_id = ?", groupID).Delete(&entity.UserGroupResource{}).Error; err != nil {
			return err
		}

		// 2. 批量插入新记录
		if len(configKeys) == 0 {
			return nil
		}
		records := make([]*entity.UserGroupResource, 0, len(configKeys))
		for _, key := range configKeys {
			records = append(records, &entity.UserGroupResource{
				GroupID:   groupID,
				ConfigKey: key,
			})
		}
		return tx.Create(&records).Error
	})
}

func (r *userGroupRepository) DeleteResourcesByGroupID(ctx context.Context, groupID int64) error {
	return r.db.WithContext(ctx).Where("group_id = ?", groupID).Delete(&entity.UserGroupResource{}).Error
}

func (r *userGroupRepository) CountUsersByGroupID(ctx context.Context, groupID int64) (int64, error) {
	var count int64
	if err := r.db.WithContext(ctx).Model(&entity.User{}).Where("group_id = ?", groupID).Count(&count).Error; err != nil {
		return 0, err
	}
	return count, nil
}
