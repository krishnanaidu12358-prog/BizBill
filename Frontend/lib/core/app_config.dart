import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the API lives. The default works for the Android emulator
/// (10.0.2.2 is the host machine). On a real phone, set your PC's LAN IP
/// from the "Server" button on the login screen.
///
/// Platform detection uses [defaultTargetPlatform] rather than dart:io so the
/// same file compiles for mobile, desktop and a browser preview.
class AppConfig {
  static const _key = 'api_base_url';

  static String _baseUrl = _defaultBaseUrl();

  static String get baseUrl => _baseUrl;

  /// Baked in at build time by Build-APK.bat (your PC's Wi-Fi address), so a
  /// phone installed from the APK finds the API without typing anything:
  ///   flutter build apk --dart-define=API_URL=http://192.168.0.10:5000
  static const _buildUrl = String.fromEnvironment('API_URL');

  static String _defaultBaseUrl() {
    if (_buildUrl.isNotEmpty) return _buildUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) _baseUrl = saved;
  }

  static Future<void> setBaseUrl(String url) async {
    var cleaned = url.trim();
    if (cleaned.endsWith('/')) cleaned = cleaned.substring(0, cleaned.length - 1);
    if (!cleaned.startsWith('http')) cleaned = 'http://$cleaned';
    _baseUrl = cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, cleaned);
  }

  static Future<void> reset() async {
    _baseUrl = _defaultBaseUrl();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
