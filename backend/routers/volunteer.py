from fastapi import APIRouter
from fastapi.responses import JSONResponse
from models.schemas import VolunteerSignupRequest, VolunteerUpdateRequest
from datetime import datetime, timezone
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/volunteer/signup")
async def volunteer_signup(req: VolunteerSignupRequest):
    """
    Register a citizen volunteer for traffic assistance.
    Inserts with status='pending' awaiting police approval.
    """
    from main import supabase

    try:
        now_iso = datetime.now(timezone.utc).isoformat()
        result = supabase.table("volunteer_assignments").insert({
            "citizen_id": req.citizen_id,
            "date": req.date,
            "start_time": req.start_time,
            "end_time": req.end_time,
            "junction": req.junction,
            "status": "pending",
            "created_at": now_iso,
        }).execute()

        row = result.data[0] if result.data else {"citizen_id": req.citizen_id}
        return {
            "id": row.get("id", ""),
            "status": "pending",
            "message": "Awaiting police approval",
        }

    except Exception as e:
        logger.error(f"POST /api/volunteer/signup error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )


@router.patch("/api/volunteer/{volunteer_id}")
async def update_volunteer(volunteer_id: str, req: VolunteerUpdateRequest):
    """
    Approve or reject a volunteer assignment.
    Sends FCM notification if approved.
    """
    from main import supabase
    from services.fcm_service import send_fcm_notification

    if req.status not in ("approved", "rejected"):
        return JSONResponse(
            status_code=422,
            content={"error": "status must be 'approved' or 'rejected'"},
        )

    try:
        now_iso = datetime.now(timezone.utc).isoformat()
        result = (
            supabase.table("volunteer_assignments")
            .update({
                "status": req.status,
                "reviewed_by": req.reviewed_by,
                "reviewed_at": now_iso,
            })
            .eq("id", volunteer_id)
            .execute()
        )

        updated_row = result.data[0] if result.data else {}

        # Send FCM notification to citizen if approved
        if req.status == "approved" and updated_row:
            citizen_id = updated_row.get("citizen_id", "")
            junction = updated_row.get("junction", "")
            date = updated_row.get("date", "")
            # Fetch FCM token for citizen (stored in citizens/users table)
            try:
                user_result = (
                    supabase.table("citizens")
                    .select("fcm_token")
                    .eq("id", citizen_id)
                    .execute()
                )
                user_data = user_result.data[0] if user_result.data else {}
                fcm_token = user_data.get("fcm_token", "")
                if fcm_token:
                    await send_fcm_notification(
                        token=fcm_token,
                        title="Volunteer Assignment Approved ✅",
                        body=f"You're confirmed for {junction} on {date}. Thank you for helping Bengaluru!",
                        data={"type": "volunteer_approved", "volunteer_id": volunteer_id},
                    )
            except Exception as fcm_e:
                logger.warning(f"FCM notification failed for volunteer {volunteer_id}: {fcm_e}")

        return {"success": True, "volunteer": updated_row}

    except Exception as e:
        logger.error(f"PATCH /api/volunteer/{volunteer_id} error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )


@router.get("/api/volunteer")
async def list_volunteers(status: str = "all", junction: str = None):
    """List volunteer assignments for police review."""
    from main import supabase

    try:
        query = (
            supabase.table("volunteer_assignments")
            .select("*")
            .order("date")
            .limit(50)
        )
        if status != "all":
            query = query.eq("status", status)
        if junction:
            query = query.eq("junction", junction)

        result = query.execute()
        return {"volunteers": result.data or [], "count": len(result.data or [])}

    except Exception as e:
        logger.error(f"GET /api/volunteer error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )
