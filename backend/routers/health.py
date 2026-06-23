from fastapi import APIRouter
from datetime import datetime, timezone

router = APIRouter()


@router.get("/api/health")
async def health_check():
    """Returns API health status with current timestamp."""
    return {
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
