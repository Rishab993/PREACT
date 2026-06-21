# PREACT Frontend Features

## Citizen

### Dashboard
- Shows live traffic KPIs, map, backend alerts, and the auto-scrolling insight carousel.
- Uses backend event and alert data where available.

### Alerts
- Read-only alert timeline.
- Uses `GET /api/alerts`.
- Displays `zone`, `message_en`, `severity`, `created_at`, and `valid_until`.

### Complaints
- Citizen complaint submission with photo upload.
- Uses `POST /api/complaints`.
- Shows backend `confidence_score` and backend `status`; the UI does not auto-reject.

### Volunteer Signup
- Citizen manually enters `citizen_id`.
- Uses `POST /api/volunteer/signup`.
- Sends exactly `citizen_id`, `date`, `start_time`, `end_time`, and `junction`.
- Shows the backend response.

### Voice
- Voice overlay and voice tab.
- Supports start/stop recording, text chat, role-aware requests, and TTS playback.

## Police

### Dashboard
- Shows command KPIs, map, backend alerts, and the auto-scrolling insight carousel.

### Alerts
- Police can create alerts with `POST /api/alerts`.
- Dashboard and Alerts page display backend alerts.

### Complaint Review
- Feature documented for the product scope.
- Current frontend navigation hides complaints from Police as requested.

### Volunteer Approval
- Police can review pending, approved, and rejected volunteer assignments.

### Deploy
- Uses backend event names for event selection.
- Supports officer selection, deployment optimization, map assignment review, and plan confirmation.

### Shadow Analysis
- Uses backend event names for event selection.
- Loads shadow comparison from the backend for the selected event.

### Ground Truth
- Uses backend event names for event selection.
- Captures actual junction stress, bottlenecks, officer count, plan-followed status, and notes.

### Forecast
- Shows zone forecast charts and confidence ranges.

### Simulation
- Populates upcoming events from backend data.
- Lets users adjust officers and barricades, then posts scenarios to the simulator backend.

### Voice
- Voice assistant sends role as `police`.

### Memory
- Searches and displays institutional memory and event debrief information.

## Footer

All datasets used for displayed information, analytics and forecasting were derived from the provided AstraM traffic management dataset for the respective police station.
