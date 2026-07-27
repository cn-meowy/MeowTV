/// User profile models — mirrors Web ProfileResp, DeviceInfo.
class UserProfile {
  final int id;
  final String username;
  final String nickname;
  final String avatar;
  final int role;
  final int status;

  const UserProfile({
    required this.id,
    required this.username,
    required this.nickname,
    required this.avatar,
    required this.role,
    required this.status,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id'] as int? ?? 0,
    username: j['username'] as String? ?? '',
    nickname: j['nickname'] as String? ?? '',
    avatar: j['avatar'] as String? ?? '',
    role: j['role'] as int? ?? 0,
    status: j['status'] as int? ?? 1,
  );
}

class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final int deviceType;
  final int lastActiveAt;
  final bool online;
  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.lastActiveAt,
    required this.online,
  });
  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
    deviceId: j['device_id'] as String? ?? '',
    deviceName: j['device_name'] as String? ?? '',
    deviceType: j['device_type'] as int? ?? 0,
    lastActiveAt: j['last_active_at'] as int? ?? 0,
    online: j['online'] as bool? ?? false,
  );
}

class DeviceListResponse {
  final List<DeviceInfo> devices;
  const DeviceListResponse({required this.devices});
  factory DeviceListResponse.fromJson(Map<String, dynamic> j) => DeviceListResponse(
    devices: (j['devices'] as List<dynamic>?)
            ?.map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}
