import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the current macOS process is signed with a Developer certificate.
///
/// When `CODE_SIGN_IDENTITY = "-"` (ad-hoc signing), the `keychain-access-groups`
/// entitlement is unavailable, causing `flutter_secure_storage` to throw
/// `PlatformException(-34018)`. We detect this by checking the code-signing
/// identity of the main executable.
bool _isMacOSDeveloperSigned() {
  if (!Platform.isMacOS) return true;
  final result = Process.runSync(
    '/usr/bin/codesign',
    ['-dvv', Platform.resolvedExecutable],
  );
  // A Developer-signed binary will have a team identifier line like:
  //   TeamIdentifier=ABC123DEF4
  // An ad-hoc signed binary will show:
  //   TeamIdentifier=not set
  final output = result.stderr.toString();
  return !output.contains('TeamIdentifier=not set');
}

/// Stores remembered login credentials: username, password, server, protocol.
class RememberedCredentials {
  final String username;
  final String password;
  final String server; // Server address without protocol prefix
  final String protocol; // Protocol prefix: 'https://' or 'http://'

  const RememberedCredentials({
    required this.username,
    required this.password,
    required this.server,
    required this.protocol,
  });
}

/// Centralised secure storage wrapper for tokens and small key-value data.
///
/// On macOS, when the app is signed with an ad-hoc identity (no Developer
/// certificate), the Keychain entitlement `keychain-access-groups` is not
/// available, causing `flutter_secure_storage` to throw
/// `PlatformException(-34018)`. This class automatically falls back to
/// [SharedPreferences] in that scenario so the app continues to work.
///
/// For remembered credentials, an additional layer of AES-256-CBC encryption
/// is applied on top of the storage layer, keyed to device identity so that
/// even if the raw storage is extracted, the credentials remain protected.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  /// Whether [init] has been called to eagerly probe Keychain availability.
  bool _initialized = false;

  // ---- Login state keys ----
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _isLoggedInKey = 'is_logged_in';
  static const _hasSeenDisclaimer = 'has_seen_disclaimer';
  static const _themeModeKey = 'theme_mode';
  static const _doubanImageProxyModeKey = 'douban_image_proxy_mode';
  static const _bufferModeKey = 'buffer_mode';
  static const _bufferQualityKey = 'buffer_quality';
  static const _autoCacheSizeLimitKey = 'auto_cache_size_limit';
  static const _playModeKey = 'play_mode';

  // ---- Remember-me keys (AES-encrypted) ----
  static const _rememberMeFlagKey = 'remember_me_flag';
  static const _rememberedCredentialsKey = 'remembered_credentials';

  // ---- Fixed salt for key derivation ----
  // This is not a secret — it prevents trivial derivation of the AES key.
  // The actual security comes from the device-unique component.
  static const _keyDerivationSalt = 'MeowTV_v1_salt_2024';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Whether Keychain is available on the current platform.
  /// `null` = not yet probed, `true` = available, `false` = unavailable.
  bool? _keychainAvailable;

  /// In-memory cache used by the SharedPreferences fallback so that
  /// synchronous callers don't need to await reads after the first load.
  final Map<String, String> _cache = {};

  /// Lazily derived AES-256 key. Null until first use.
  encrypt.Key? _aesKey;

  // ------------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------------

  /// Eagerly probes Keychain availability so that subsequent [read]/[write]/[delete]
  /// calls can use a synchronous check instead of `await _probeKeychain()`.
  ///
  /// Call this once during app startup (e.g. in `main()`).
  Future<void> init() async {
    if (_initialized) return;
    await _probeKeychain();
    _initialized = true;
  }

  // ------------------------------------------------------------------
  // Keychain availability probe
  // ------------------------------------------------------------------

  /// Probes whether `flutter_secure_storage` can successfully write and
  /// read a value. The result is cached so subsequent calls are free.
  Future<bool> _probeKeychain() async {
    if (_keychainAvailable != null) return _keychainAvailable!;

    // Only macOS needs the fallback; other platforms should work fine.
    if (!Platform.isMacOS) {
      _keychainAvailable = true;
      return true;
    }

    // Short-circuit: if the app is ad-hoc signed (no Developer certificate),
    // the Keychain entitlement is unavailable, so skip the probe entirely.
    if (!_isMacOSDeveloperSigned()) {
      debugPrint('[SecureStorage] Ad-hoc signing detected, using '
          'SharedPreferences fallback');
      _keychainAvailable = false;
      return false;
    }

    const probeKey = '__keychain_probe__';
    try {
      await _storage.write(key: probeKey, value: 'ok');
      final result = await _storage.read(key: probeKey);
      await _storage.delete(key: probeKey);
      _keychainAvailable = result == 'ok';
    } catch (e) {
      debugPrint('[SecureStorage] Keychain unavailable, falling back to '
          'SharedPreferences: $e');
      _keychainAvailable = false;
    }
    return _keychainAvailable!;
  }

  // ------------------------------------------------------------------
  // Core read / write / delete with fallback
  // ------------------------------------------------------------------

  Future<String?> read({required String key}) async {
    if (_keychainAvailable == true || await _probeKeychain()) {
      return _storage.read(key: key);
    }
    // Fallback: SharedPreferences
    if (_cache.containsKey(key)) return _cache[key];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  Future<void> write({required String key, required String value}) async {
    if (_keychainAvailable == true || await _probeKeychain()) {
      await _storage.write(key: key, value: value);
      return;
    }
    // Fallback: SharedPreferences
    _cache[key] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> delete({required String key}) async {
    if (_keychainAvailable == true || await _probeKeychain()) {
      await _storage.delete(key: key);
      return;
    }
    // Fallback: SharedPreferences
    _cache.remove(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<void> deleteAll() async {
    if (_keychainAvailable == true || await _probeKeychain()) {
      await _storage.deleteAll();
      return;
    }
    // Fallback: SharedPreferences
    _cache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Alias for [deleteAll] – clears all stored data.
  Future<void> clearAll() => deleteAll();

  // ------------------------------------------------------------------
  // AES-256-CBC encryption helpers
  // ------------------------------------------------------------------

  /// Derives a 32-byte AES key from device identity + app package + salt.
  ///
  /// The key is stable per device+app combination, so encrypted credentials
  /// can be decrypted on the same device after app restart.
  Future<encrypt.Key> _deriveKey() async {
    if (_aesKey != null) return _aesKey!;

    final deviceInfo = DeviceInfoPlugin();
    String deviceId;

    if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      deviceId = info.identifierForVendor ?? '';
    } else if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      deviceId = info.id; // Hardware serial / FINGERPRINT
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      // MacOsDeviceInfo has hostname but no stable unique ID on non-Apple Silicon
      deviceId = info.computerName.isNotEmpty ? info.computerName : Platform.resolvedExecutable;
    } else if (Platform.isWindows) {
      final info = await deviceInfo.windowsInfo;
      deviceId = info.deviceId;
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
      deviceId = info.machineId ?? info.versionId ?? '';
    } else {
      // Fallback: use a random-ish stable string
      deviceId = Platform.resolvedExecutable;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final packageName = packageInfo.packageName;

    // Derive: SHA-256(deviceId + packageName + salt)
    final keyMaterial = '$deviceId:$packageName:$_keyDerivationSalt';
    final hash = sha256.convert(utf8.encode(keyMaterial));
    _aesKey = encrypt.Key(Uint8List.fromList(hash.bytes));
    return _aesKey!;
  }

  /// Encrypts [plaintext] using AES-256-CBC with a random IV.
  ///
  /// Returns a string in the format: `base64(iv):base64(ciphertext)`
  Future<String> _encrypt(String plaintext) async {
    final key = await _deriveKey();
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    // Format: base64(iv):base64(ciphertext)
    return '${base64.encode(iv.bytes)}:${encrypted.base64}';
  }

  /// Decrypts a string produced by [_encrypt].
  Future<String> _decrypt(String encrypted) async {
    final parts = encrypted.split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid encrypted format: expected "base64(iv):base64(ciphertext)"');
    }
    final ivBytes = base64.decode(parts[0]);
    final ciphertext = parts[1];

    final key = await _deriveKey();
    final iv = encrypt.IV(ivBytes);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc),
    );
    return encrypter.decrypt64(ciphertext, iv: iv);
  }

  // ------------------------------------------------------------------
  // Typed accessors
  // ------------------------------------------------------------------

  // ---- Access Token ----
  Future<String?> getAccessToken() => read(key: _accessTokenKey);
  Future<void> setAccessToken(String token) =>
      write(key: _accessTokenKey, value: token);
  Future<void> removeAccessToken() => delete(key: _accessTokenKey);

  // ---- Refresh Token ----
  Future<String?> getRefreshToken() => read(key: _refreshTokenKey);
  Future<void> setRefreshToken(String token) =>
      write(key: _refreshTokenKey, value: token);
  Future<void> removeRefreshToken() => delete(key: _refreshTokenKey);

  // ---- Login State ----
  Future<bool> isLoggedIn() async {
    final val = await read(key: _isLoggedInKey);
    return val == 'true';
  }

  Future<void> setLoggedIn(bool value) =>
      write(key: _isLoggedInKey, value: value.toString());

  // ---- Disclaimer ----
  Future<bool> hasSeenDisclaimer() async {
    final val = await read(key: _hasSeenDisclaimer);
    return val == 'true';
  }

  Future<void> setHasSeenDisclaimer(bool value) =>
      write(key: _hasSeenDisclaimer, value: value.toString());

  // ---- Theme Mode ----
  Future<String?> getThemeMode() => read(key: _themeModeKey);
  Future<void> setThemeMode(String mode) =>
      write(key: _themeModeKey, value: mode);

  // ---- Douban Image Proxy Mode ----
  Future<String?> getDoubanImageProxyMode() => read(key: _doubanImageProxyModeKey);
  Future<void> setDoubanImageProxyMode(String mode) =>
      write(key: _doubanImageProxyModeKey, value: mode);

  // ---- Buffer Mode ----
  Future<String?> getBufferMode() => read(key: _bufferModeKey);
  Future<void> setBufferMode(String mode) =>
      write(key: _bufferModeKey, value: mode);

  // ---- Buffer Quality ----
  Future<String?> getBufferQuality() => read(key: _bufferQualityKey);
  Future<void> setBufferQuality(String quality) =>
      write(key: _bufferQualityKey, value: quality);

  // ---- Auto Cache Size Limit ----
  Future<String?> getAutoCacheSizeLimit() => read(key: _autoCacheSizeLimitKey);
  Future<void> setAutoCacheSizeLimit(String limit) =>
      write(key: _autoCacheSizeLimitKey, value: limit);

  // ---- Play Mode ----
  Future<String?> getPlayMode() => read(key: _playModeKey);
  Future<void> setPlayMode(String mode) => write(key: _playModeKey, value: mode);

  // ------------------------------------------------------------------
  // Remember-me credentials (AES-encrypted)
  // ------------------------------------------------------------------

  /// Whether the "Remember Me" checkbox was checked on the last successful login.
  Future<bool> isRememberMeEnabled() async {
    final val = await read(key: _rememberMeFlagKey);
    return val == 'true';
  }

  /// Sets the remember-me flag.
  Future<void> setRememberMeFlag(bool value) =>
      write(key: _rememberMeFlagKey, value: value.toString());

  /// Saves remembered credentials (username, password, server, protocol).
  /// All fields are AES-encrypted before storage.
  Future<void> saveRememberedCredentials({
    required String username,
    required String password,
    required String server,
    required String protocol,
  }) async {
    // Serialize to JSON
    final json = jsonEncode({
      'username': username,
      'password': password,
      'server': server,
      'protocol': protocol,
    });
    // Encrypt and store
    final encrypted = await _encrypt(json);
    await write(key: _rememberedCredentialsKey, value: encrypted);
    await setRememberMeFlag(true);
  }

  /// Retrieves remembered credentials if any.
  /// Returns null if no credentials are stored.
  Future<RememberedCredentials?> getRememberedCredentials() async {
    final isEnabled = await isRememberMeEnabled();
    if (!isEnabled) return null;

    final encrypted = await read(key: _rememberedCredentialsKey);
    if (encrypted == null || encrypted.isEmpty) return null;

    try {
      final json = await _decrypt(encrypted);
      final map = jsonDecode(json) as Map<String, dynamic>;
      return RememberedCredentials(
        username: map['username'] as String,
        password: map['password'] as String,
        server: map['server'] as String,
        protocol: map['protocol'] as String,
      );
    } catch (e) {
      debugPrint('[SecureStorage] Failed to decrypt remembered credentials: $e');
      // Corrupt data — clear it to avoid repeated failures
      await clearRememberedCredentials();
      return null;
    }
  }

  /// Clears all remembered credentials and the remember-me flag.
  Future<void> clearRememberedCredentials() async {
    await delete(key: _rememberedCredentialsKey);
    await delete(key: _rememberMeFlagKey);
  }
}
