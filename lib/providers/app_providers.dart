import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/bootstrap/startup_timer.dart';

// ─── Theme Provider ──────────────────────────────────────────────────────────
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool('isDarkMode') ?? true;
      state = isDark ? ThemeMode.dark : ThemeMode.light;
      StartupTimer.mark('Theme preference loaded');
    } catch (e) {
      debugPrint('[ThemeNotifier] Error loading: $e');
      state = ThemeMode.dark;
    }
  }

  Future<void> toggle() async {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', state == ThemeMode.dark);
    } catch (e) {
      debugPrint('[ThemeNotifier] Error saving: $e');
    }
  }

  bool get isDark => state == ThemeMode.dark;
}

// ─── Language Provider ────────────────────────────────────────────────────────
enum AppLanguage { en, kn }

extension AppLanguageX on AppLanguage {
  bool get isKannada => this == AppLanguage.kn;
  Locale get locale => this == AppLanguage.kn
      ? const Locale('kn', 'IN')
      : const Locale('en', 'IN');
}

final languageProvider = StateNotifierProvider<LanguageNotifier, AppLanguage>((ref) {
  return LanguageNotifier();
});

class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier() : super(AppLanguage.en) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('language') ?? 'en';
      state = code == 'kn' ? AppLanguage.kn : AppLanguage.en;
      StartupTimer.mark('Translation preference loaded');
    } catch (e) {
      debugPrint('[LanguageNotifier] Error loading: $e');
      state = AppLanguage.en;
    }
  }

  Future<void> toggle() async {
    state = state == AppLanguage.en ? AppLanguage.kn : AppLanguage.en;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', state.name);
    } catch (e) {
      debugPrint('[LanguageNotifier] Error saving: $e');
    }
  }

  bool get isKannada => state == AppLanguage.kn;

  Locale get locale => state == AppLanguage.kn
      ? const Locale('kn', 'IN')
      : const Locale('en', 'IN');
}

// ─── Nav Index Provider ───────────────────────────────────────────────────────
final navIndexProvider = StateProvider<int>((ref) => 0);

// ─── Zone Selection Provider ──────────────────────────────────────────────────
final selectedZoneProvider = StateProvider<String?>((ref) => null);

// ─── Selected Event Provider ──────────────────────────────────────────────────
final selectedEventIdProvider = StateProvider<String?>((ref) => null);

// ─── Voice Assistant Overlay ──────────────────────────────────────────────────
final voiceOverlayOpenProvider = StateProvider<bool>((ref) => false);

// ─── App Role ─────────────────────────────────────────────────────────────────
enum AppRole { citizen, police }

final roleProvider = StateNotifierProvider<RoleNotifier, AppRole?>((ref) {
  return RoleNotifier();
});

class RoleNotifier extends StateNotifier<AppRole?> {
  RoleNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString('app_role');
      if (val == 'citizen') {
        state = AppRole.citizen;
      } else if (val == 'police') {
        state = AppRole.police;
      }
      StartupTimer.mark('Role preference loaded (${state?.name ?? "none"})');
    } catch (e) {
      debugPrint('[RoleNotifier] Error loading: $e');
    }
  }

  Future<void> select(AppRole role) async {
    state = role;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_role', role.name);
    } catch (e) {
      debugPrint('[RoleNotifier] Error saving: $e');
    }
  }

  Future<void> reset() async {
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_role');
    } catch (e) {
      debugPrint('[RoleNotifier] Error resetting: $e');
    }
  }

  bool get isCitizen => state == AppRole.citizen;
  bool get isPolice => state == AppRole.police;
}
