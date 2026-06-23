"""
IsolationForest anomaly detection + OSM venue density queries.
Fitted once at startup; runs every 30 minutes via APScheduler.
"""
import logging
from datetime import datetime, timezone, timedelta
from typing import Optional

import httpx
import numpy as np
from sklearn.ensemble import IsolationForest

logger = logging.getLogger(__name__)

# Module-level model — populated at startup
iso_model: Optional[IsolationForest] = None

# Known high-traffic venues with real Bengaluru coordinates
VENUES = [
    {"name": "Chinnaswamy Stadium", "lat": 12.9785, "lng": 77.5996, "zone": "Central Zone 2"},
    {"name": "Silk Board", "lat": 12.9172, "lng": 77.6233, "zone": "South Zone 1"},
    {"name": "Hebbal Flyover", "lat": 13.0412, "lng": 77.5955, "zone": "North Zone 1"},
    {"name": "Mekhri Circle", "lat": 13.0063, "lng": 77.5857, "zone": "Central Zone 1"},
    {"name": "Electronic City", "lat": 12.8456, "lng": 77.6603, "zone": "South Zone 2"},
    {"name": "Yeshwanthpura Circle", "lat": 13.0319, "lng": 77.5347, "zone": "West Zone 1"},
    {"name": "KR Circle", "lat": 12.9767, "lng": 77.5713, "zone": "Central Zone 1"},
]


def fit_on_startup(supabase_client) -> None:
    """
    Pull historical events and fit IsolationForest.
    Called once at FastAPI startup. ~20MB memory footprint.
    """
    global iso_model
    try:
        logger.info("Fitting IsolationForest on historical events data...")
        result = (
            supabase_client.table("events")
            .select("start_dt,zone,severity_proxy,priority,status")
            .not_.is_("severity_proxy", "null")
            .execute()
        )
        rows = result.data or []

        if len(rows) < 10:
            logger.warning(f"Only {len(rows)} rows for IsolationForest — using dummy model")
            iso_model = IsolationForest(contamination=0.1, random_state=42)
            iso_model.fit(np.random.rand(50, 5))
            return

        features = []
        for row in rows:
            try:
                start_dt_str = row.get("start_dt") or ""
                if start_dt_str:
                    dt = datetime.fromisoformat(start_dt_str.replace("Z", "+00:00"))
                    hour_of_day = dt.hour
                    day_of_week = dt.weekday()
                else:
                    hour_of_day = 12
                    day_of_week = 0

                severity = float(row.get("severity_proxy") or 0.5)
                is_high_priority = 1 if str(row.get("priority", "")).lower() == "high" else 0
                has_road_closure = 1 if "closure" in str(row.get("status", "")).lower() else 0

                features.append([hour_of_day, day_of_week, severity, is_high_priority, has_road_closure])
            except Exception as inner_e:
                logger.debug(f"Skipping row in IsoForest fit: {inner_e}")
                continue

        if len(features) < 10:
            logger.warning("Not enough valid feature rows — using dummy IsolationForest")
            iso_model = IsolationForest(contamination=0.1, random_state=42)
            iso_model.fit(np.random.rand(50, 5))
            return

        feature_matrix = np.array(features)
        iso_model = IsolationForest(contamination=0.1, random_state=42)
        iso_model.fit(feature_matrix)
        logger.info(f"IsolationForest fitted on {len(features)} events")

    except Exception as e:
        logger.error(f"IsolationForest startup fit failed: {e}")
        # Fallback: dummy model so the app doesn't crash
        iso_model = IsolationForest(contamination=0.1, random_state=42)
        iso_model.fit(np.random.rand(50, 5))


async def get_osm_venue_density(lat: float, lng: float, radius_m: int = 500) -> float:
    """
    Query OSM Overpass API for nearby amenity nodes — no API key required.
    Returns normalised density 0.0–1.0.
    """
    query = f"""
    [out:json];
    node(around:{radius_m},{lat},{lng})[amenity];
    out count;
    """
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(
                "https://overpass-api.de/api/interpreter",
                params={"data": query},
            )
            response.raise_for_status()
            data = response.json()
            count = data.get("elements", [{}])[0].get("tags", {}).get("nodes", 0)
            if isinstance(count, str):
                count = int(count)
            return min(count / 100.0, 1.0)
    except Exception as e:
        logger.warning(f"OSM query failed for ({lat},{lng}): {e} — defaulting to 0.3")
        return 0.3


async def run_anomaly_check(supabase_client) -> None:
    """
    Called every 30 minutes by APScheduler.
    Checks each venue for anomalous activity and inserts alerts if detected.
    """
    global iso_model

    if iso_model is None:
        logger.warning("IsolationForest not fitted — skipping anomaly check")
        return

    from services.groq_service import generate_answer

    now_utc = datetime.now(timezone.utc)
    hour_of_day = now_utc.hour
    day_of_week = now_utc.weekday()
    valid_until = (now_utc + timedelta(hours=4)).isoformat()

    for venue in VENUES:
        try:
            venue_density = await get_osm_venue_density(venue["lat"], venue["lng"])
            feature = np.array([[hour_of_day, day_of_week, venue_density, 1, 0]])
            score = iso_model.decision_function(feature)[0]

            if score < -0.1:
                logger.info(f"Anomaly detected at {venue['name']} (score={score:.3f})")

                # Insert into anomaly_signals
                try:
                    supabase_client.table("anomaly_signals").insert({
                        "zone": venue["zone"],
                        "venue_name": venue["name"],
                        "score": float(score),
                        "alert_triggered": True,
                        "detected_at": now_utc.isoformat(),
                    }).execute()
                except Exception as db_e:
                    logger.warning(f"Could not insert anomaly_signal: {db_e}")

                # Build bilingual alert message
                msg_en = (
                    f"Unusual activity detected near {venue['name']}. "
                    "Officers pre-positioning recommended."
                )
                try:
                    msg_kn = await generate_answer(
                        f"Translate to Kannada: {msg_en}",
                        "",
                        "Translate only, no explanation.",
                    )
                except Exception:
                    msg_kn = msg_en

                # Insert alert
                try:
                    supabase_client.table("alerts").insert({
                        "zone": venue["zone"],
                        "corridor": None,
                        "message_en": msg_en,
                        "message_kn": msg_kn,
                        "severity": 0.75,
                        "valid_until": valid_until,
                        "created_at": now_utc.isoformat(),
                    }).execute()
                    logger.info(f"Alert inserted for {venue['name']}")
                except Exception as alert_e:
                    logger.error(f"Could not insert alert for {venue['name']}: {alert_e}")

        except Exception as e:
            logger.error(f"Anomaly check error for {venue['name']}: {e}")
            continue
