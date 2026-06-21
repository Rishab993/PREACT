import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralized application configuration.
///
/// All values are read exclusively from [dotenv] — no hardcoded fallbacks
/// for secrets or service URLs. Call [AppConfig.validate] during startup
/// (before any service initialisation) to fail fast with a clear error
/// message when a required variable is absent.
class AppConfig {
  AppConfig._();

  // ── Required variables ────────────────────────────────────────────────────

  /// Supabase project URL, e.g. `https://abc123.supabase.co`
  static String get supabaseUrl => _require('SUPABASE_URL');

  /// Supabase anonymous (public) API key (JWT).
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  /// Base URL for the PREACT backend API,
  /// e.g. `https://preact-api.onrender.com`
  static String get apiBase => _require('PREACT_API_BASE');

  // ── Optional variables (safe public defaults) ─────────────────────────────

  /// OpenStreetMap (or custom) tile URL template.
  /// Uses the public OSM tile server if not set — no credentials required.
  static String get mapTileUrl =>
      dotenv.maybeGet('MAP_TILE_URL') ??
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // ── Startup validation ────────────────────────────────────────────────────

  /// Required env variable names that must be present at startup.
  static const List<String> _requiredKeys = [
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'PREACT_API_BASE',
  ];

  /// Validates that all required environment variables are present.
  ///
  /// Throws a [ConfigException] naming the first missing variable.
  /// Call this from `main()` after loading `.env` and before any service
  /// initialisation.
  static void validate() {
    if (!dotenv.isInitialized) {
      throw ConfigException(
        'dotenv is not initialised. '
        'Ensure dotenv.load() is called before AppConfig.validate().',
        missingKey: null,
      );
    }

    for (final key in _requiredKeys) {
      final value = dotenv.maybeGet(key);
      if (value == null || value.trim().isEmpty) {
        throw ConfigException(
          'Required environment variable "$key" is missing or empty. '
          'Add it to your .env file.',
          missingKey: key,
        );
      }
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Returns the value for [key] or throws [ConfigException] if absent.
  static String _require(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.trim().isEmpty) {
      throw ConfigException(
        'Required environment variable "$key" is missing or empty. '
        'Add it to your .env file.',
        missingKey: key,
      );
    }
    return value.trim();
  }
}

/// Thrown when a required environment variable is absent or empty.
class ConfigException implements Exception {
  /// Human-readable error message.
  final String message;

  /// The name of the missing variable, or `null` if dotenv itself is not ready.
  final String? missingKey;

  const ConfigException(this.message, {required this.missingKey});

  @override
  String toString() => 'ConfigException: $message';
}
