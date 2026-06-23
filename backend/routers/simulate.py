from fastapi import APIRouter
from fastapi.responses import JSONResponse
from models.schemas import SimulateRequest
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/simulate")
async def run_simulation(req: SimulateRequest):
    """
    Run XGBoost traffic simulation for a deployment scenario.
    Returns per-junction 24h severity curves + summary.
    Latency target: < 1s.
    """
    from main import supabase
    from services.simulate_service import run_simulation

    try:
        scenario_dicts = [s.model_dump() for s in req.scenario]
        result = run_simulation(req.event_id, scenario_dicts, supabase)
        return {"event_id": req.event_id, **result}
    except Exception as e:
        logger.error(f"POST /api/simulate error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Simulation failed", "detail": str(e)},
        )
