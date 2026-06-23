# PREACT

**Proactive Resource Allocation & Event-Adaptive Command Tool**

A dual-role mobile and web application for Bengaluru Traffic Police. PREACT provides citizens with a portal to report violations, view alerts, and volunteer for traffic assistance and gives the police command center real-time traffic monitoring, 72-hour predictive forecasting, OR-Tools-based deployment optimization, traffic simulation, and post-event learning.

Built for the **Flipkart GRIDLOCK 2.0 Hackathon**
Problem Statement: **Event-Driven Congestion (Planned & Unplanned)**

---

## Table of Contents

- [Problem Statement](#problem-statement)
- [Solution Overview](#solution-overview)
- [Dataset](#dataset)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Installation](#installation)
- [Running the App](#running-the-app)
- [Backend Setup](#backend-setup)
- [Features](#features)
- [API Reference](#api-reference)
- [Roles](#roles)

---

## Problem Statement

Political rallies, festivals, sports events, construction activities, and sudden gatherings create localized traffic breakdowns in Bengaluru. Current challenges:

- Event impact is not quantified in advance
- Resource deployment is experience-driven, not data-driven
- No post-event learning or regret analysis system exists

PREACT addresses all three gaps.

---

## Solution Overview

PREACT operates across five phases for any traffic event:

1. **Event Intake** → Citizens report violations with photo evidence; backend scores confidence and detects duplicates; police review and approve or reject complaints
2. **Forecasting** → Prophet model generates 72-hour zone-level severity forecasts with confidence intervals; XGBoost scores severity
3. **Deployment** → OR-Tools optimizer computes optimal officer placement across junctions given constraints; manual override via map
4. **Live Monitoring** → Supabase Realtime pushes alerts via WebSocket to both citizen and police clients simultaneously
5. **Post-Event Learning** → Structured debrief captures ground truth; Shadow Ops computes regret score and congestion avoided; data is indexed for future forecast training

---

## Dataset

The predictive forecasting and institutional memory features are built on the **ASTraM anonymized event dataset**  8,204 real traffic incident records from Bengaluru, provided as part of the Flipkart GRIDLOCK 2.0 hackathon.

Dataset: [Gridlock 2.0 Hackathon ASTraM Dataset](https://uc.hackerearth.com/he-public-ap-south-1/Astram%20event%20data_anonymized%20-%20Astram%20event%20data_anonymizedb40ac87.csv)

Each record contains: event type (planned/unplanned), latitude/longitude, event cause (vehicle breakdown, tree fall, road closure, others), corridor, priority (High/Medium/Low), zone, junction, start and end datetimes, resolution status, and police station.

This dataset is used to:
- Train the Prophet model for 72-hour zone-level severity forecasting
- Score severity confidence via XGBoost
- Seed institutional memory for similar-event retrieval via `/api/memory/similar/:eventId`
- Provide historical context in Shadow Ops and Ground Truth analysis screens

---

## Architecture

```
Clients (Flutter  Android / Web)
    |
    | REST (HTTPS)
    v
RESTful API Layer
    |-- Citizen APIs:      /api/complaints, /api/alerts, /api/volunteer
    |-- Intelligence APIs: /api/forecast/:zone, /api/insights, /api/kpi
    |-- Operations APIs:   /api/officers/deploy, /api/simulator/run, /api/debrief
    |-- Memory APIs:       /api/events/search, /api/events/:id
    |
    |-- Supabase           (Auth, Storage, Postgres, Realtime)
    |-- Predictive Engine  (Prophet + XGBoost)
    |-- OR-Tools Optimizer (Officer deployment)
    |-- Image Validator    (Format, size, blur check)
    |
    v
Data Layer
    |-- Supabase Postgres  (Events, Complaints, Volunteers, Alerts, Officers)
    |-- Local Cache        (sqflite + shared_preferences, offline support)

Supabase Realtime → WebSocket push → both clients (bypasses REST)
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter 3.x (Android + Web) |
| State Management | Flutter Riverpod 2.5.1 |
| HTTP Client | Dio 5.4.3 |
| Auth / DB / Realtime | Supabase Flutter 2.5.6 |
| Maps | flutter_map 6.2.1 + latlong2 + OpenStreetMap |
| Charts | fl_chart 0.68.0 |
| Voice Input | record 5.2.1 |
| Voice Output | flutter_tts 4.0.2 |
| Audio Playback | audioplayers 6.0.0 |
| Local Storage | shared_preferences 2.2.3 |
| Environment | flutter_dotenv 5.1.0 |
| Typography | google_fonts 6.2.1 |
| ML Forecasting | Prophet (72hr severity forecast) |
| ML Scoring | XGBoost (severity confidence scoring) |
| Optimization | OR-Tools CP-SAT (officer deployment) |
| Anomaly Detection | IsolationForest (unplanned gathering detection) |
| Causal Analysis | DoWhy (counterfactual regret scoring) |
| Backend Framework | FastAPI (Python) |
| Background Jobs | APScheduler |
| Database | Supabase (PostgreSQL + PostGIS) |

---

## Project Structure

```
PREACT/
├── lib/
│   ├── main.dart
│   ├── preact_app.dart
│   ├── core/
│   │   ├── api/{api_client,api_parsers,endpoints}.dart
│   │   ├── auth/supabase_service.dart
│   │   ├── bootstrap/{preact_bootstrap,startup_coordinator,startup_splash_screen,startup_timer}.dart
│   │   ├── config/app_config.dart
│   │   ├── theme/{app_theme,colors,text_styles}.dart
│   │   └── utils/complaint_image_url.dart
│   ├── features/
│   │   ├── alerts/alerts_screen.dart
│   │   ├── assistant/voice_assistant_overlay.dart
│   │   ├── auth/role_selection_screen.dart
│   │   ├── complaints/complaints_screen.dart
│   │   ├── dashboard/dashboard_screen.dart
│   │   ├── deployment/deployment_screen.dart
│   │   ├── forecast/forecast_screen.dart
│   │   ├── ground_truth/ground_truth_screen.dart
│   │   ├── memory/memory_screen.dart
│   │   ├── shadow/shadow_screen.dart
│   │   ├── simulator/simulator_screen.dart
│   │   └── volunteer/volunteer_screen.dart
│   ├── shared/
│   │   ├── models/models.dart
│   │   └── widgets/{alert_card,app_footer,app_shell,app_toggles,brand_logo,
│   │             complaint_image,glass_card,kpi_tile,lazy_indexed_stack,
│   │             officer_card,severity_gauge,skeleton_loader}.dart
│   └── providers/{app_providers,data_providers}.dart
├── backend/
│   ├── main.py
│   ├── scheduler.py
│   ├── requirements.txt
│   ├── routers/
│   │   ├── health.py
│   │   ├── events.py
│   │   ├── forecast.py
│   │   ├── deployment.py
│   │   ├── simulate.py
│   │   ├── complaints.py
│   │   ├── alerts.py
│   │   ├── counterfactual.py
│   │   ├── ground_truth.py
│   │   ├── volunteer.py
│   │   ├── memory.py
│   │   └── chat.py
│   ├── services/
│   │   ├── forecast_service.py
│   │   ├── anomaly_service.py
│   │   └── fcm_service.py
│   └── models/
├── android/
├── web/
├── assets/fonts/ & images/preact_logo.png
├── docs/FEATURES.md
├── test/widget_test.dart
├── pubspec.yaml
└── pubspec.lock
```

---

## Prerequisites

- Flutter SDK `>=3.0.0 <4.0.0`
- Dart SDK `>=3.0.0`
- Android Studio or VS Code with Flutter extension
- A Supabase project (free tier is sufficient)
- Android device or emulator (API 21+), or Chrome for web

Verify your Flutter installation:

```bash
flutter doctor
```

---

## Environment Setup

Create a `.env` file in the project root. This file is loaded by `flutter_dotenv` at runtime.

```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
API_BASE_URL=your_backend_api_base_url
```

**Where to find these values:**
- `SUPABASE_URL` and `SUPABASE_ANON_KEY`: Supabase dashboard → Project Settings → API
- `API_BASE_URL`: The live backend is already deployed  use `https://preact-gcbu.onrender.com`

The `.env` file is declared as an asset in `pubspec.yaml` and must be present before running the app. It is listed in `.gitignore` and is never committed.

---

## Installation

Clone the repository:

```bash
git clone https://github.com/Rishab993/PREACT.git
cd PREACT
```

Install Flutter dependencies:

```bash
flutter pub get
```

---

## Running the App

**Android:**

```bash
flutter run
```

**Web (Chrome):**

```bash
flutter run -d chrome
```

**Release build (Android APK):**

```bash
flutter build apk --release
```

**Release build (Web):**

```bash
flutter build web --release
```

---

## Backend Setup

The PREACT backend is a FastAPI server running 5 ML models (Prophet, XGBoost, IsolationForest, OR-Tools CP-SAT, DoWhy) in a single process. It connects to Supabase for the database and runs 3 APScheduler background jobs (forecast every 6h, anomaly detection every 30min, post-event officer nudge every 15min).

###  Live Deployment

The backend is live on Render and ready to use without any local setup:

> **Base URL:** `https://preact-gcbu.onrender.com`
> **Swagger Docs:** [https://preact-gcbu.onrender.com/docs](https://preact-gcbu.onrender.com/docs)
> **ReDoc:** [https://preact-gcbu.onrender.com/redoc](https://preact-gcbu.onrender.com/redoc)

The Flutter app is pre-configured to point to this deployment. No local backend setup is needed to run the app.

---

### Local Backend Setup (Optional)

If you want to run the backend locally:

#### Prerequisites
- Python 3.10+
- A Supabase project (free tier works)

#### 1. Navigate to the backend folder

```bash
cd backend
```

#### 2. Create and activate a virtual environment

```bash
python -m venv venv
source venv/bin/activate        # macOS / Linux
venv\Scripts\activate           # Windows
```

#### 3. Install dependencies

```bash
pip install -r requirements.txt
```

>  `prophet` requires `pystan` which may take a few minutes to compile on first install. This is expected.

#### 4. Set up environment variables

Create a `.env` file inside the `backend/` directory:

```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_SERVICE_KEY=your_supabase_service_role_key
```

>  Use the **Service Role Key** (not the Anon Key) for the backend  it needs full DB access to run the ML pipeline and scheduler jobs. Find it in Supabase dashboard → Project Settings → API → `service_role` key.

#### 5. Start the server

```bash
uvicorn main:app --reload
```

The API will be available at `http://localhost:8000`
Swagger docs at `http://localhost:8000/docs`

#### 6. What happens on startup

On launch, the server automatically:
1. Connects to Supabase using your credentials
2. Fits the **IsolationForest** model on historical event data
3. Starts **APScheduler** with 3 background jobs:
   - Forecast pipeline  runs every **6 hours**
   - Anomaly detection  runs every **30 minutes**
   - Post-event officer nudge (FCM push)  runs every **15 minutes**
4. Registers all **12 API routers**

---

## Features

### Citizen Portal

- **Report Complaint**  violation type, zone, description, photo upload (JPG/PNG/WebP, max 5MB), GPS validation, backend confidence scoring and duplicate detection
- **View Live Alerts**  traffic, event, emergency, weather, road work alerts with severity indicators; auto-refresh every 15 seconds
- **Volunteer Signup**  citizen ID, junction, date, time slot; status pending until police approval
- **Voice Assistant**  available on all screens via FAB; microphone or text input; English and Kannada; TTS output

### Police Command Center

- **Dashboard**  active events, officers deployed, open complaints, active alerts KPIs; AI insights carousel; live Bengaluru map with zone severity polygons; zone sparklines; alert feed
- **Create Alerts**  title, zone, category, severity, message in English and Kannada, issuer
- **Complaint Validation**  tab view (Pending / Valid / Rejected / All); filters by zone, violation type, confidence score; approve or reject with reason
- **Volunteer Management**  tab view (Pending / Approved / Rejected); approve or reject signups
- **72hr Forecast**  Prophet-generated zone-level severity graph with 80% confidence interval; zone selector; all-zones grid with severity gauges
- **Deployment Planner**  auto-optimize via OR-Tools CP-SAT; manual assignment via map tap; heatmap toggle; results panel with junction assignments
- **Traffic Simulator**  junction officer sliders (0–10); barricade toggles; real-time severity curves; save and load scenarios
- **Shadow Ops**  PREACT plan vs actual deployment bar chart; regret score gauge; congestion avoided metric; similar past events
- **Ground Truth / Debrief**  junction stress sliders; bottleneck cause chips; actual officer count; plan-followed toggle; notes field
- **Memory**  full-text historical event search; filters by zone, event type, attendance; event detail view; insight panel

---

## API Reference

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/health` | Health check |
| GET | `/api/events` | List all events |
| GET | `/api/officers` | List all officers |
| GET | `/api/forecast/:zone` | 72-hour zone forecast |
| POST | `/api/deploy` | Deploy officers to zones/junctions |
| GET | `/api/counterfactual` | Counterfactual analysis |
| GET | `/api/shadow/:eventId` | Shadow ops analysis for an event |
| GET | `/api/complaints` | List complaints |
| POST | `/api/complaints` | Submit complaint (multipart) |
| PATCH | `/api/complaints/:id` | Approve or reject complaint |
| POST | `/api/chat` | Voice assistant chat |
| GET | `/api/alerts` | List active alerts |
| POST | `/api/alerts` | Create alert |
| PATCH | `/api/alerts/:id` | Update alert |
| POST | `/api/volunteer/signup` | Sign up volunteer |
| GET | `/api/volunteer` | List volunteers |
| PATCH | `/api/volunteer/:id` | Approve or reject volunteer |
| POST | `/api/simulate` | Run traffic simulation |
| POST | `/api/ground-truth` | Submit post-event debrief |
| GET | `/api/memory/search` | Full-text search past events |
| GET | `/api/memory/similar/:eventId` | Find similar past events |

Full interactive documentation: [https://preact-gcbu.onrender.com/docs](https://preact-gcbu.onrender.com/docs)

---

## Roles

The app supports two roles selectable at launch. A role switcher button is available in the top bar on all screens for testing features of both sides without restarting the app.

| Role | Access |
|---|---|
| Citizen | Dashboard, Alerts, Raise Complaint, Volunteer Signup, Voice Assistant |
| Police Command Center | Full feature set including Forecast, Deployment, Simulator, Shadow Ops, Debrief, Memory |

---

*Built for Bengaluru Traffic Police. Flipkart GRIDLOCK 2.0  Event-Driven Congestion track.*
