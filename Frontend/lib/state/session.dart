import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/models.dart';
import 'appearance.dart';

/// Holds the signed-in account and exposes the configured [ApiClient].
class Session extends ChangeNotifier {
  Session({required this.appearance});

  /// Theme settings stored on the account are pushed here after sign-in.
  final Appearance appearance;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUser = 'user_profile';

  String? _accessToken;
  String? _refreshToken;
  UserProfile? _user;
  bool _restoring = true;

  late final ApiClient api = ApiClient(
    tokenProvider: () => _accessToken,
    onUnauthorized: _clearLocal,
  );

  UserProfile? get user => _user;
  bool get isLoggedIn => _accessToken != null && _user != null;
  bool get isRestoring => _restoring;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_kAccess);
    _refreshToken = prefs.getString(_kRefresh);
    final raw = prefs.getString(_kUser);
    if (raw != null) {
      try {
        _user = UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        _user = null;
      }
    }

    // Confirm the stored token is still good; otherwise start clean.
    if (_accessToken != null) {
      try {
        final res = await api.get('/api/auth/me');
        _user = UserProfile.fromJson(res.data as Map<String, dynamic>);
        await _persist();
        await appearance.applyFromServer(_user!.themeMode, _user!.themeName);
      } on ApiException {
        await _clearLocal();
      }
    }

    _restoring = false;
    notifyListeners();
  }

  Future<UserProfile> login(String mobile, String password) async {
    final res = await api.post('/api/auth/login',
        body: {'mobile': mobile, 'password': password});
    return _acceptAuth(res.data as Map<String, dynamic>);
  }

  Future<UserProfile> registerBusiness(Map<String, dynamic> body) async {
    final res = await api.post('/api/auth/register-business', body: body);
    return _acceptAuth(res.data as Map<String, dynamic>);
  }

  Future<UserProfile> registerCustomer(Map<String, dynamic> body) async {
    final res = await api.post('/api/auth/register-customer', body: body);
    return _acceptAuth(res.data as Map<String, dynamic>);
  }

  Future<UserProfile> _acceptAuth(Map<String, dynamic> data) async {
    _accessToken = data['accessToken'] as String?;
    _refreshToken = data['refreshToken'] as String?;
    _user = UserProfile.fromJson(data['user'] as Map<String, dynamic>);
    await _persist();
    await appearance.applyFromServer(_user!.themeMode, _user!.themeName);
    notifyListeners();
    return _user!;
  }

  /// Keeps the cached profile in step after the appearance screen saves.
  Future<void> updateCachedProfile(UserProfile profile) async {
    _user = profile;
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/api/auth/logout');
    } catch (_) {
      // Signing out locally matters more than the server round trip.
    }
    await _clearLocal();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) await prefs.setString(_kAccess, _accessToken!);
    if (_refreshToken != null) await prefs.setString(_kRefresh, _refreshToken!);
    if (_user != null) await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
  }

  Future<void> _clearLocal() async {
    _accessToken = null;
    _refreshToken = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUser);
    notifyListeners();
  }
}
