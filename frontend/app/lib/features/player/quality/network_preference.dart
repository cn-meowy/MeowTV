import 'package:shared_preferences/shared_preferences.dart';
import 'quality_level.dart';

/// 网络清晰度偏好设置
class NetworkPreference {
  static const _wifiKey = 'quality_wifi_preference';
  static const _cellularKey = 'quality_cellular_preference';
  static const _wifiSpecificKey = 'quality_wifi_specific_level';
  static const _cellularSpecificKey = 'quality_cellular_specific_level';

  /// 获取 WiFi 网络下的默认清晰度偏好
  static Future<QualityPreference> getWifiPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_wifiKey);
    if (value == null) return QualityPreference.highest;
    return QualityPreference.values.firstWhere(
      (e) => e.name == value,
      orElse: () => QualityPreference.highest,
    );
  }

  /// 获取蜂窝网络下的默认清晰度偏好
  static Future<QualityPreference> getCellularPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_cellularKey);
    if (value == null) return QualityPreference.medium;
    return QualityPreference.values.firstWhere(
      (e) => e.name == value,
      orElse: () => QualityPreference.medium,
    );
  }

  /// 设置 WiFi 偏好
  static Future<void> setWifiPreference(QualityPreference pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wifiKey, pref.name);
  }

  /// 设置蜂窝偏好
  static Future<void> setCellularPreference(QualityPreference pref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cellularKey, pref.name);
  }

  /// 获取 WiFi 指定清晰度等级 ID
  static Future<String?> getWifiSpecificLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_wifiSpecificKey);
  }

  /// 设置 WiFi 指定清晰度等级 ID
  static Future<void> setWifiSpecificLevel(String levelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wifiSpecificKey, levelId);
  }

  /// 获取蜂窝指定清晰度等级 ID
  static Future<String?> getCellularSpecificLevel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cellularSpecificKey);
  }

  /// 设置蜂窝指定清晰度等级 ID
  static Future<void> setCellularSpecificLevel(String levelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cellularSpecificKey, levelId);
  }

  /// 根据偏好和可用等级列表获取推荐清晰度
  static QualityLevel? getRecommendedLevel(
    QualityPreference preference,
    List<QualityLevel> levels, {
    String? specificLevelId,
  }) {
    if (levels.isEmpty) return null;
    final sorted = List<QualityLevel>.from(levels)
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    switch (preference) {
      case QualityPreference.highest:
        return sorted.first;
      case QualityPreference.lowest:
        return sorted.last;
      case QualityPreference.medium:
        final midIndex = sorted.length ~/ 2;
        return sorted[midIndex];
      case QualityPreference.specific:
        if (specificLevelId != null) {
          return levels.where((l) => l.id == specificLevelId).firstOrNull;
        }
        return sorted.first;
      case QualityPreference.auto:
        return null; // auto 模式由 ABR 决定
    }
  }
}
