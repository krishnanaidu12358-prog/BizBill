import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the chosen light/dark mode and colour palette.
///
/// The value is cached locally so the app starts in the right theme without
/// waiting for the network, and pushed to the account so it follows the user
/// to another device.
class Appearance extends ChangeNotifier {
  static const _kMode = 'theme_mode';
  static const _kPalette = 'theme_palette';

  ThemeMode _mode = ThemeMode.system;
  String _palette = 'Classic';

  ThemeMode get mode => _mode;
  String get palette => _palette;

  String get modeName => switch (_mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  static ThemeMode parseMode(String? name) => switch (name) {
        'Light' => ThemeMode.light,
        'Dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = parseMode(prefs.getString(_kMode));
      _palette = prefs.getString(_kPalette) ?? 'Classic';
    } catch (_) {
      // Fall back to the defaults if storage is unavailable.
    }
    notifyListeners();
  }

  /// Applies what the server has on the account (called after login / restore).
  Future<void> applyFromServer(String? modeName, String? paletteKey) async {
    _mode = parseMode(modeName);
    if (paletteKey != null && paletteKey.isNotEmpty) _palette = paletteKey;
    await _persist();
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    await _persist();
    notifyListeners();
  }

  Future<void> setPalette(String key) async {
    _palette = key;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMode, modeName);
      await prefs.setString(_kPalette, _palette);
    } catch (_) {
      // A failed cache write is not worth interrupting the user for.
    }
  }
}
