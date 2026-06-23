from fastapi import APIRouter
from fastapi.responses import JSONResponse
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/api/memory/search")
async def search_memory(
    q: str = "",
    zone: str = None,
    event_type: str = None,
    min_attendance: int = 0,
):
    """
    Full-text search over event debriefs.
    Supports keyword search, zone, event_type, min_attendance filters.
    Latency target: < 800ms.
    """
    from main import supabase
    from services.memory_service import search_debriefs

    try:
        results = await search_debriefs(
            q=q,
            zone=zone,
            event_type=event_type,
            min_attendance=min_attendance,
            supabase_client=supabase,
        )
        return {"results": results, "count": len(results), "query": q}
    except Exception as e:
        logger.error(f"GET /api/memory/search error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )


@router.get("/api/memory/similar/{event_id}")
async def similar_events(event_id: str):
    """
    Find top 3 historically similar events by zone + cause + attendance.
    Latency target: < 500ms.
    """
    from main import supabase
    from services.memory_service import find_similar_events

    try:
        results = await find_similar_events(event_id, supabase)
        return {"event_id": event_id, "similar": results, "count": len(results)}
    except Exception as e:
        logger.error(f"GET /api/memory/similar/{event_id} error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )
