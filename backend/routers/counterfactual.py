from fastapi import APIRouter
from fastapi.responses import JSONResponse
from models.schemas import CounterfactualRequest
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/counterfactual")
async def run_counterfactual(req: CounterfactualRequest):
    """
    Run DoWhy causal inference for a given event.
    Estimates minutes saved by following PREACT recommendations.
    """
    from main import supabase
    from services.dowhy_service import run_counterfactual

    try:
        result = run_counterfactual(req.event_id, supabase)
        return {"event_id": req.event_id, **result}
    except Exception as e:
        logger.error(f"POST /api/counterfactual error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Counterfactual analysis failed", "detail": str(e)},
        )


@router.get("/api/shadow/{event_id}")
async def get_shadow_comparison(event_id: str):
    """
    Side-by-side comparison of PREACT vs manual deployments for an event.
    Queries deployments table split by source field.
    """
    from main import supabase

    try:
        result = (
            supabase.table("deployments")
            .select(
                "officer_id,junction,lat,lng,start_time,end_time,priority,source,"
                "officers!inner(name,badge_number,zone)"
            )
            .eq("event_id", event_id)
            .execute()
        )
        rows = result.data or []

        preact_plan = [r for r in rows if r.get("source") == "preact"]
        manual_plan = [r for r in rows if r.get("source") == "manual"]

        # Fetch debrief summary
        debrief = {}
        try:
            d_result = (
                supabase.table("event_debriefs")
                .select("actual_congestion,preact_congestion_estimate,congestion_avoided_minutes,regret_score")
                .eq("event_id", event_id)
                .execute()
            )
            if d_result.data:
                data = d_result.data[0]
                debrief = {
                    "actual_congestion": data.get("actual_congestion"),
                    "preact_estimate": data.get("preact_congestion_estimate"),
                    "avoided_minutes": data.get("congestion_avoided_minutes"),
                    "regret_score": data.get("regret_score"),
                }
        except Exception:
            pass

        return {
            "event_id": event_id,
            "preact_plan": preact_plan,
            "manual_plan": manual_plan,
            "preact_count": len(preact_plan),
            "manual_count": len(manual_plan),
            "debrief": debrief,
        }

    except Exception as e:
        logger.error(f"GET /api/shadow/{event_id} error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )
