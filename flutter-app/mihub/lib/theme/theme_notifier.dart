// lib/theme/theme_notifier.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeNotifier extends ChangeNotifier {
  static const _key = 'app_theme_mode';

  // Green is the default. On first launch (no saved preference) the app
  // opens with the Terminal Green theme. The user can switch in Settings.
  AppThemeMode _mode = AppThemeMode.green;
  AppThemeMode get mode => _mode;

  AppThemeTokens get tokens =>
      _mode == AppThemeMode.green ? AppThemeTokens.green : AppThemeTokens.blue;

  ThemeData get themeData => AppTheme.buildTheme(_mode);

  ThemeNotifier() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    // Only override the default if the user has explicitly saved a preference.
    if (saved == 'blue') {
      _mode = AppThemeMode.blue;
      notifyListeners();
    }
    // 'green' or null (first launch) → keep green default, no notify needed.
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode == AppThemeMode.green ? 'green' : 'blue');
  }
}