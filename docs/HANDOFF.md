# PREACT Handoff Documentation

This document describes the architecture, API contracts, deployment configurations, and mobile build details for PREACT (Police Command & Crowd Management System).

---

## 1. Architecture Overview

PREACT is built using Flutter and Riverpod for state management. It connects to:
- A custom backend API server (configured via environment variables).
- Supabase (for database replication, real-time streams, authentication, and file storage).

### Key Directories
- `lib/core/`: Application themes, configurations, API client configurations, and bootstrap scripts.
- `lib/features/`: Core feature modules (dashboard, complaints, alerts, volunteer management, voice assistance, deployment, simulators).
- `lib/providers/`: Global Riverpod state providers for data models and app shell navigation/role management.
- `lib/shared/`: Shared models (e.g., `AlertModel`, `ComplaintModel`, `VolunteerModel`) and reusable UI widgets.

---

## 2. Feature Flows & Subsystems

### A. Citizen & Officer Dashboard
- **Location:** `lib/features/dashboard/dashboard_screen.dart`
- **Insights Carousel:** Scrollable AI insights card updated via dynamic PageView page tracking timer.
- **KPI Summary:** Fetches active events, active alerts, open complaints, deployed officers, and pending volunteer counts from the backend via Riverpod (`kpiProvider`).
- **Interactive Map:** Interactive `flutter_map` showing police zones, live junctions, and color-coded traffic severity areas.

### B. Volunteer Signup & Approvals
- **Location:** `lib/features/volunteer/volunteer_screen.dart`
- **Citizen Flow:** Automatically loads the user's UUID (`citizen_id`) from local SharedPreferences and displays it as read-only. Form validation ensures citizen IDs are strictly UUID format before posting.
- **Police Flow:** Displays tabbed list of volunteers grouped by status (`pending`, `approved`, `rejected`). Police officers can approve or reject signups, triggering updates directly to the backend.

### C. Complaint System
- **Location:** `lib/features/complaints/complaints_screen.dart`
- **Citizen Submission:** Form validation requiring image upload. Submits complaints to the backend containing `violation_type`, coordinate floats, `zone`, and `description`.
- **Duplicate Suppression & Quality checks:** Post-submission dialog displays duplicate warning if same violation was reported nearby, along with confidence score bar.
- **Police Review Queue:** Kanban-like interface showing complaints categorized by status with confidence scores visible on individual cards.

### D. Alerts Feed
- **Location:** `lib/features/alerts/`
- **Tick Interval:** Automatically refreshes the alerts feed every 15 seconds.
- **Auto-invalidating Cache:** Creating a new alert automatically invalidates Riverpod providers (`alertsProvider` and `alertsListProvider`), immediately fetching fresh alerts.

---

## 3. API Contract Specifications

### Create Alert (`POST /api/alerts`)
Posts details of city-wide emergency alerts.
- **Payload:**
  ```json
  {
    "title": "Title",
    "category": "accident",
    "severity": 0.8,
    "zone": "Central Zone 1",
    "message_en": "Description in English",
    "message_kn": "ಕನ್ನಡದಲ್ಲಿ ವಿವರಣೆ",
    "issuer": "Police Control",
    "valid_from": "2026-06-19T05:00:00Z",
    "valid_until": "2026-06-19T08:00:00Z"
  }
  ```

### File Complaint (`POST /api/complaints`)
Submits a citizen complaint with image upload via MultipartFormData.
- **Payload (Multipart Form):**
  - `violation_type`: String (e.g., `illegal_parking`, `accident`)
  - `lat`: Double
  - `lng`: Double
  - `zone`: String
  - `description`: String
  - `image`: Binary file payload

### Volunteer Signup (`POST /api/volunteer/signup`)
- **Payload:**
  ```json
  {
    "citizen_id": "UUID-String",
    "date": "YYYY-MM-DD",
    "start_time": "HH:MM:00",
    "end_time": "HH:MM:00",
    "junction": "Junction Name"
  }
  ```

---

## 4. Deployment & Configurations

### A. Environment Configuration (`.env`)
The app uses `flutter_dotenv` to load runtime properties. Check `.env` at the project root:
```properties
API_URL=http://your-backend-api-url:8000
SUPABASE_URL=https://your-supabase-project.supabase.co
SUPABASE_KEY=your-anon-key
```

### B. Network Traffic Security (Android)
To facilitate testing against local or non-SSL staging endpoints, the Android app has `android:usesCleartextTraffic="true"` configured inside `AndroidManifest.xml`.

---

## 5. Android Build Guidelines

Ensure the following constraints are met for local APK generation:
1. **Minimum SDK Level:** Explicitly set to `21` inside `android/app/build.gradle.kts` to satisfy dependencies.
2. **Permissions Enabled:**
   - `INTERNET` & `ACCESS_NETWORK_STATE` (Network operations)
   - `RECORD_AUDIO` (Voice input module)
   - `CAMERA` & `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` (Image upload)
   - `ACCESS_FINE_LOCATION` & `ACCESS_COARSE_LOCATION` (Map coordinates)

### Command to build Android Debug APK:
```bash
flutter build apk --debug
```
