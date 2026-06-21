# Android Compatibility Audit

Audit date: 2026-06-19  
Platform: Flutter (PREACT Traffic Command App)

## Summary

The project had **no Android platform folder** initially. Android support was added via `flutter create . --platforms=android`, with permissions, dependency fixes, and cross-platform audio recording updates.

## Web-Only / Platform Risk Findings

| Finding | Location | Resolution |
|---------|----------|------------|
| No `dart:html` imports | — | None found in `lib/` |
| No `window` / `document` browser APIs | — | None found in `lib/` |
| No hardcoded `localhost` URLs | — | All API URLs from `.env` via `AppConfig` |
| `localStorage` reference | `supabase_service.dart` | Supabase `EmptyLocalStorage()` auth option — cross-platform, not browser localStorage |
| Web blob fetch in voice assistant | `voice_assistant_overlay.dart` | Guarded with `kIsWeb`; native uses `dart:io` + `path_provider` |
| `record_linux` / `record_platform_interface` version mismatch | `pubspec.yaml` | Pinned `record_platform_interface: 1.2.0` via `dependency_overrides` |

## Packages Used (Cross-Platform Status)

| Package | Android | Notes |
|---------|---------|-------|
| `dio` | OK | HTTP client |
| `supabase_flutter` | OK | DB/realtime fallback |
| `flutter_map` | OK | OSM tiles |
| `record` | OK | Mic recording (after override fix) |
| `flutter_tts` | OK | Speech output |
| `image_picker` | OK | Complaint photo upload |
| `shared_preferences` | OK | Role/theme/citizen_id persistence |
| `path_provider` | OK | Temp audio file path on Android |
| `google_fonts` | OK | Runtime font fetch (needs network on first load) |

## Files Changed for Android

| File | Why |
|------|-----|
| `android/` (entire tree) | Created Android project scaffold |
| `android/app/src/main/AndroidManifest.xml` | Added INTERNET, RECORD_AUDIO, CAMERA, READ_MEDIA_IMAGES permissions; app label PREACT |
| `pubspec.yaml` | `record` bump + `dependency_overrides` for compile fix |
| `lib/features/assistant/voice_assistant_overlay.dart` | `path_provider` temp paths for native recording; improved stop/start flow |
| `lib/providers/data_providers.dart` | API-first alerts/events/officers (no web-only deps) |
| `lib/core/api/api_parsers.dart` | Shared JSON list parsing for backend responses |
| `lib/shared/models/models.dart` | Flexible officer field mapping for `/api/officers` |
| `lib/features/deployment/deployment_screen.dart` | Fixed deploy payload `officer_ids`; separate loading states |
| `lib/features/alerts/alerts_screen.dart` | GET/POST `/api/alerts` integration |
| `lib/features/complaints/complaints_screen.dart` | Spec-compliant form + confidence display |
| `lib/features/volunteer/volunteer_screen.dart` | Backend-required signup fields |
| `lib/app_router.dart` | Role-correct nav module order |
| `lib/shared/widgets/app_shell.dart` | Footer, nav labels, removed gradient button |
| `lib/shared/widgets/app_footer.dart` | AstraM dataset attribution |
| `lib/shared/widgets/brand_logo.dart` | Larger header branding |
| `lib/features/dashboard/dashboard_screen.dart` | Auto-scrolling insights carousel; live alerts feed |
| `lib/core/api/endpoints.dart` | Correct incident type constants |
| `test/widget_test.dart` | Fixed smoke test import |
| `docs/FEATURES.md` | Feature/API documentation |

## Remaining Blockers / Notes

1. **Release signing:** APK built with debug signing config (default from `flutter create`). Production release needs a release keystore.
2. **Application ID:** Still `com.example.preact_app` — should be changed to production package name before store submission.
3. **Google Fonts:** First launch may download fonts over network; consider bundling for offline judges/demo.
4. **record package:** Uses `dependency_overrides` — upgrade to `record` 7.x when ready for long-term maintenance.
5. **Supabase realtime:** Used as fallback only; primary data path is REST API.

## Permissions Declared

- `INTERNET` — API + map tiles + fonts
- `RECORD_AUDIO` — Voice assistant
- `CAMERA` — Image picker (camera source)
- `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE` — Gallery photo upload
