"""
XGBoost-based traffic simulation service.
Uses the already-loaded xgb_model from forecast_service.
Latency target: < 1s.
"""
import logging
from datetime import datetime
from typing import Optional, Any

import numpy as np

logger = logging.getLogger(__name__)


def _get_xgb_model(supabase_client) -> Optional[Any]:
    """Retrieve xgb_model — from forecast_service memory, or Supabase Storage fallback."""
    from services.forecast_service import xgb_model
    if xgb_model is not None:
        return xgb_model

    # Fallback: try loading from Supabase Storage
    try:
        import pickle
        logger.info("xgb_model not in memory — attempting load from Supabase Storage")
        data = supabase_client.storage.from_("models").download("xgb_latest.pkl")
        model = pickle.loads(data)
        return model
    except Exception as e:
        logger.warning(f"Could not load xgb_model from storage: {e}")
        return None


def _encode_cause(cause: str) -> int:
    cause_map = {
        "Festival": 0, "Sports": 1, "Concert": 2, "Protest": 3,
        "Accident": 4, "Construction": 5, "VIP Movement": 6, "Other": 7,
    }
    return cause_map.get(str(cause).strip(), 7)


def _encode_corridor(corridor: str) -> int:
    corridors = [
        "CBD 1", "CBD 2", "Mysore Road", "Tumkur Road", "Bellary Road 1",
        "Bellary Road 2", "Hosur Road", "Bannerghatta Road", "ORR East 1",
        "ORR East 2", "ORR North 1", "ORR North 2", "Magadi Road",
        "Old Madras Road", "West of Chord Road", "Old Airport Road",
        "Varthur Road", "Hennur Main Road", "IRR(Thanisandra road)",
        "Airport New South Road",
    ]
    try:
        return corridors.index(str(corridor).strip())
    except ValueError:
        return 0


def run_simulation(event_id: str, scenario_params: list[dict], supabase_client) -> dict:
    """
    Predict per-junction severity curves for a custom deployment scenario.

    scenario_params: [{junction, officer_count, start_time, barricade_active}]

    Returns:
    {
      zones: [{zone, junction, severity_curve: [float×24], peak_hour: int, risk_tier: str}],
      summary: {total_congestion_min: float, vs_optimal_delta: float, recommendation: str}
    }
    """
    try:
        # Fetch event data
        event_result = (
            supabase_client.table("events")
            .select("zone,corridor,event_cause,expected_attendance,start_dt")
            .eq("id", event_id)
            .execute()
        )
        event_data = event_result.data[0] if event_result.data else {}
        zone = event_data.get("zone", "Central Zone 1")
        corridor = event_data.get("corridor", "CBD 1")
        event_cause = event_data.get("event_cause", "Other")
        expected_attendance = float(event_data.get("expected_attendance") or 5000)

        # Parse start hour
        start_dt_str = event_data.get("start_dt", "")
        try:
            start_hour = datetime.fromisoformat(start_dt_str.replace("Z", "+00:00")).hour
        except Exception:
            start_hour = 18  # evening default

        model = _get_xgb_model(supabase_client)
        logger.warning(f"Simulation model loaded = {model is not None}")
        logger.info(f"Simulation model loaded? {model is not None}")
        attendance_norm = min(expected_attendance / 50000.0, 1.0)
        cause_enc = _encode_cause(event_cause)
        corridor_enc = _encode_corridor(corridor)

        zones_output = []
        total_severity = 0.0

        # Baseline: from forecasts table if model unavailable
        baseline_rows = []
        if model is None:
            try:
                fc_result = (
                    supabase_client.table("forecasts")
                    .select("severity,forecast_hour")
                    .eq("zone", zone)
                    .order("forecast_hour")
                    .limit(24)
                    .execute()
                )
                baseline_rows = fc_result.data or []
            except Exception as fc_e:
                logger.warning(f"Could not fetch baseline forecasts: {fc_e}")

        for scenario in scenario_params:
            junction = scenario.get("junction", "Unknown Junction")
            officer_count = int(scenario.get("officer_count", 1))
            barricade_active = 1 if scenario.get("barricade_active", False) else 0

            severity_curve = []
            for h in range(24):
                hour = (start_hour + h) % 24
                day_of_week = datetime.now().weekday()

                if model is not None:
                    features = [
                        [
                            officer_count,
                            barricade_active,
                            hour,
                            day_of_week,
                            attendance_norm,
                            cause_enc,
                            corridor_enc,
                        ]
                    ]
                    try:
                        # XGBoost predicts tier (0-3), convert back to severity midpoint
                        tier = int(model.predict(np.array(features))[0])    
                        tier_midpoints = [0.175, 0.475, 0.7, 0.9]
                        raw_sev = tier_midpoints[min(tier, 3)]
                        # Reduce severity with more officers / barricade
                        officer_factor = max(0.5, 1.0 - (officer_count - 1) * 0.1)
                        barricade_factor = 0.85 if barricade_active else 1.0
                        sev = float(np.clip(raw_sev * officer_factor * barricade_factor, 0.0, 1.0))
                    except Exception as pred_e:
                        logger.exception(pred_e)
                        sev = 0.5
                else:
                # Intelligent fallback when XGBoost model is unavailable
                
                    if h < len(baseline_rows):
                        base = float(baseline_rows[h].get("severity", 0.5))
                    else:
                        base = 0.5

                    # officers reduce congestion
                    officer_modifier = min(officer_count * 0.04, 0.25)

                    # barricades help a bit
                    barricade_modifier = 0.10 if barricade_active else 0.0

                    # attendance increases congestion
                    attendance_modifier = attendance_norm * 0.20

                    # morning and evening peaks
                    peak_modifier = 0.0
                    if hour in [8, 9, 10]:
                        peak_modifier += 0.08
                    elif hour in [17, 18, 19, 20]:
                        peak_modifier += 0.12

                    sev = (
                        base
                        + attendance_modifier
                        + peak_modifier
                        - officer_modifier
                        - barricade_modifier
                    )

                    sev = float(np.clip(sev, 0.05, 0.95))

                severity_curve.append(round(sev, 4))

            peak_hour = int(np.argmax(severity_curve))
            peak_sev = severity_curve[peak_hour]

            if peak_sev > 0.8:
                risk_tier = "CRITICAL"
            elif peak_sev > 0.6:
                risk_tier = "HIGH"
            elif peak_sev > 0.35:
                risk_tier = "MEDIUM"
            else:
                risk_tier = "LOW"

            total_severity += sum(severity_curve)
            zones_output.append({
                "zone": zone,
                "junction": junction,
                "severity_curve": severity_curve,
                "peak_hour": peak_hour,
                "risk_tier": risk_tier,
            })

        # Summary statistics
        avg_severity = total_severity / (len(scenario_params) * 24) if scenario_params else 0.5
        total_congestion_min = round(avg_severity * 60 * len(scenario_params), 1)
        vs_optimal_delta = round((avg_severity - 0.35) * 60, 1)  # delta vs LOW tier

        if avg_severity > 0.7:
            recommendation = "Deploy additional officers to high-severity junctions immediately."
        elif avg_severity > 0.5:
            recommendation = "Current deployment is moderate — consider barricades at peak junctions."
        else:
            recommendation = "Deployment plan looks optimal. Monitor live situation."

        # Persist simulation result
        try:
            supabase_client.table("simulations").insert({
                "event_id": event_id,
                "scenario_params": scenario_params,
                "result_zones": zones_output,
                "total_congestion_min": total_congestion_min,
                "vs_optimal_delta": vs_optimal_delta,
                "created_at": datetime.now().isoformat(),
            }).execute()
        except Exception as db_e:
            logger.warning(f"Could not persist simulation: {db_e}")

        return {
            "zones": zones_output,
            "summary": {
                "total_congestion_min": total_congestion_min,
                "vs_optimal_delta": vs_optimal_delta,
                "recommendation": recommendation,
            },
        }

    except Exception as e:
        logger.error(f"Simulation error: {e}")
        return {
            "zones": [],
            "summary": {
                "total_congestion_min": 0.0,
                "vs_optimal_delta": 0.0,
                "recommendation": "Simulation failed — using manual deployment.",
            },
        }
