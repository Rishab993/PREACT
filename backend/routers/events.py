from fastapi import APIRouter
from fastapi.responses import JSONResponse
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/api/events")
async def get_events():
    """
    Returns upcoming and recent events for Flutter event list.
    Queries the latest 100 events ordered by start_dt DESC.
    """
    from main import supabase

    try:
        result = (
            supabase.table("events")
            .select(
                "id,event_cause,description,start_dt,end_datetime,"
                "lat,lng,zone,corridor,junction,status,priority"
            )
            .order("start_dt", desc=True)
            .limit(100)
            .execute()
        )
        return {"events": result.data, "count": len(result.data)}
    except Exception as e:
        logger.error(f"Error fetching events: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )
