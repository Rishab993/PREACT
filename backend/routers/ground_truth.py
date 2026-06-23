from fastapi import APIRouter, BackgroundTasks
from fastapi.responses import JSONResponse
from models.schemas import GroundTruthRequest
from datetime import datetime, timezone
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/ground-truth")
async def submit_ground_truth(req: GroundTruthRequest, background_tasks: BackgroundTasks):
    """
    Submit post-event officer observations.
    Triggers XGBoost retrain every 50 submissions (non-blocking).
    """
    from main import supabase
    from services.retrain_service import retrain_xgboost

    try:
        now_iso = datetime.now(timezone.utc).isoformat()

        # ── 1. INSERT ground truth ─────────────────────────────────────────────
        insert_data = {
            "event_id": req.event_id,
            "officer_id": req.officer_id,
            "actual_crowd_size": req.actual_crowd_size,
            "junction_stress": [js.model_dump() for js in req.junction_stress],
            "bottlenecks": req.bottlenecks,
            "notes": req.notes,
            "submitted_at": now_iso,
        }

        try:
            supabase.table("officer_ground_truth").insert(insert_data).execute()
        except Exception as db_e:
            logger.error(f"Ground truth insert failed: {db_e}")
            return JSONResponse(
                status_code=503,
                content={"error": "Database temporarily unavailable", "detail": str(db_e)},
            )

        # ── 2. Compute prediction error vs forecasts ───────────────────────────
        prediction_error = {"crowd_error": None, "severity_error": None}
        try:
            event_result = (
                supabase.table("events")
                .select("zone,expected_attendance,severity_proxy")
                .eq("id", req.event_id)
                .execute()
            )
            event_data = event_result.data[0] if event_result.data else {}
            zone = event_data.get("zone")

            fc_result = (
                supabase.table("forecasts")
                .select("severity")
                .eq("zone", zone)
                .order("forecast_hour")
                .limit(1)
                .execute()
            )
            fc_rows = fc_result.data or []

            expected_attendance = float(event_data.get("expected_attendance") or 0)
            actual_crowd = float(req.actual_crowd_size)
            crowd_error = round(
                abs(actual_crowd - expected_attendance) / max(expected_attendance, 1) * 100, 1
            )

            actual_severity = float(event_data.get("severity_proxy") or 0.5)
            forecast_severity = float(fc_rows[0].get("severity", 0.5)) if fc_rows else 0.5
            severity_error = round(abs(actual_severity - forecast_severity), 4)

            prediction_error = {
                "crowd_error": crowd_error,
                "severity_error": severity_error,
            }

            # ── 3. UPDATE event_debriefs ───────────────────────────────────────
            try:
                supabase.table("event_debriefs").upsert(
                    {
                        "event_id": req.event_id,
                        "ground_truth_error": prediction_error,
                    },
                    on_conflict="event_id",
                ).execute()
            except Exception as debrief_e:
                logger.warning(f"Could not update event_debrief: {debrief_e}")

        except Exception as err_e:
            logger.warning(f"Prediction error computation failed: {err_e}")

        # ── 4. Count total submissions → trigger retrain every 50 ──────────────
        try:
            count_result = (
                supabase.table("officer_ground_truth")
                .select("id", count="exact")
                .execute()
            )
            total_count = count_result.count or 0
            if total_count > 0 and total_count % 50 == 0:
                logger.info(f"Triggering XGBoost retrain at {total_count} ground truth rows")
                background_tasks.add_task(retrain_xgboost, supabase)
        except Exception as count_e:
            logger.warning(f"Could not check retrain trigger: {count_e}")

        return {
            "success": True,
            "prediction_error": prediction_error,
        }

    except Exception as e:
        logger.error(f"POST /api/ground-truth error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Ground truth submission failed", "detail": str(e)},
        )
