from fastapi import APIRouter
from fastapi.responses import JSONResponse
from models.schemas import ForecastRequest
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/forecast")
async def trigger_forecast(req: ForecastRequest):
    """
    Fetch or generate forecast for a specific event.
    Checks staleness (> 6h old) and runs pipeline if needed.
    """
    from main import supabase
    from services.forecast_service import get_forecast_for_event
    from fastapi import HTTPException

    try:
        rows = get_forecast_for_event(req.event_id, supabase)
        return {"event_id": req.event_id, "forecasts": rows, "count": len(rows)}
    except ValueError as val_err:
        raise HTTPException(status_code=404, detail=str(val_err))
    except Exception as e:
        logger.error(f"POST /api/forecast error: {e}")
        # Return cached data from Supabase on pipeline failure
        try:
            cached = (
                supabase.table("forecasts")
                .select("*")
                .order("forecast_hour")
                .limit(72)
                .execute()
            )
            return {
                "event_id": req.event_id,
                "forecasts": cached.data or [],
                "count": len(cached.data or []),
                "warning": "Pipeline error — returning cached data",
            }
        except Exception:
            return JSONResponse(
                status_code=503,
                content={"error": "Forecast service unavailable", "detail": str(e)},
            )


@router.get("/api/forecast/{zone}")
async def get_zone_forecast(zone: str):
    """
    Return next 72h forecast rows for a given zone.
    Used by Flutter P2 Forecast Detail screen.
    """
    from main import supabase
    from datetime import datetime, timezone, timedelta

    try:
        now = datetime.now(timezone.utc)
        end = (now + timedelta(hours=72)).isoformat()

        result = (
            supabase.table("forecasts")
            .select("zone,corridor,forecast_hour,severity,confidence_lower,confidence_upper")
            .eq("zone", zone)
            .gt("forecast_hour", now.isoformat())
            .lt("forecast_hour", end)
            .order("forecast_hour")
            .execute()
        )
        return {"zone": zone, "forecasts": result.data or [], "count": len(result.data or [])}

    except Exception as e:
        logger.error(f"GET /api/forecast/{zone} error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )
