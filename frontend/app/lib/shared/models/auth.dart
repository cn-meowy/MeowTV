/// Auth request/response models.
class LoginRequest {
  final String username;
  final String password;
  final int deviceType;
  final String deviceId;
  final String deviceName;
  LoginRequest({
    required this.username,
    required this.password,
    this.deviceType = 2, // iOS default
    required this.deviceId,
    required this.deviceName,
  });
  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'device_type': deviceType,
    'device_id': deviceId,
    'device_name': deviceName,
  };
}

class LoginResponse {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  LoginResponse({required this.accessToken, required this.refreshToken, required this.expiresIn});
  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    expiresIn: json['expires_in'] as int,
  );
}

class RefreshRequest {
  final String refreshToken;
  RefreshRequest({required this.refreshToken});
  Map<String, dynamic> toJson() => {'refresh_token': refreshToken};
}
