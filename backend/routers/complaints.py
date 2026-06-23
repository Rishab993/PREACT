import uuid
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, UploadFile, File, Form
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/complaints")
async def submit_complaint(
    image: UploadFile = File(...),
    lat: float = Form(...),
    lng: float = Form(...),
    violation_type: str = Form(...),
    zone: str = Form(...),
    exif_lat: float = Form(0.0),
    exif_lng: float = Form(0.0),
):
    """
    Submit a citizen complaint with photo evidence.
    Validates GPS, blur, and duplicates. Never silently rejects.
    """
    from main import supabase
    from services.complaint_service import validate_complaint

    try:
        image_bytes = await image.read()

        # ── Validate ──────────────────────────────────────────────────────────
        validation = validate_complaint(
            image_bytes=image_bytes,
            submitted_lat=lat,
            submitted_lng=lng,
            exif_lat=exif_lat if abs(exif_lat) > 0.001 else None,
            exif_lng=exif_lng if abs(exif_lng) > 0.001 else None,
            zone=zone,
            violation_type=violation_type,
            supabase_client=supabase,
        )

        complaint_id = str(uuid.uuid4())
        now_iso = datetime.now(timezone.utc).isoformat()

        # ── Upload image to Supabase Storage (regardless of validity) ─────────
        image_url = None
        try:
            storage_path = f"complaints/{complaint_id}.jpg"
            supabase.storage.from_("complaint-images").upload(
                storage_path,
                image_bytes,
                {"content-type": image.content_type or "image/jpeg", "upsert": "true"},
            )
            image_url = f"{storage_path}"
        except Exception as upload_e:
            logger.warning(f"Image upload failed: {upload_e}")

        # ── Insert into complaints table ──────────────────────────────────────
        # exif_lat/exif_lng are NOT in the DB schema — used only for GPS validation above
        status = "valid" if validation["valid"] else "invalid"
        try:
            insert_result = supabase.table("complaints").insert({
                "id": complaint_id,
                "lat": lat,
                "lng": lng,
                "zone": zone,
                "violation_type": violation_type,
                "image_path": image_url,
                "status": status,
                "rejection_reason": validation.get("reason"),
                "confidence_score": validation["confidence_score"],
                "submitted_at": now_iso,
            }).execute()
        except Exception as db_e:
            logger.error(f"Complaint DB insert failed: {db_e}")
            error_code = getattr(db_e, "code", None)
            if error_code and str(error_code).startswith("23"):
                msg = getattr(db_e, "message", "Database validation failed")
                return JSONResponse(
                    status_code=400,
                    content={"error": "Validation error", "detail": msg},
                )
            return JSONResponse(
                status_code=503,
                content={"error": "Database temporarily unavailable", "detail": str(db_e)},
            )

        # ── If valid: insert alert ─────────────────────────────────────────────
        if validation["valid"]:
            try:
                from datetime import timedelta
                valid_until = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
                supabase.table("alerts").insert({
                    "zone": zone,
                    "corridor": None,
                    "message_en": f"Citizen report: {violation_type} violation in {zone}.",
                    "severity": 0.6,
                    "valid_until": valid_until,
                    "created_at": now_iso,
                }).execute()
            except Exception as alert_e:
                logger.warning(f"Could not create alert from complaint: {alert_e}")

        return {
            "valid": validation["valid"],
            "reason": validation.get("reason"),
            "complaint_id": complaint_id,
            "confidence_score": validation["confidence_score"],
        }

    except Exception as e:
        logger.error(f"POST /api/complaints error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Complaint submission failed", "detail": str(e)},
        )


@router.get("/api/complaints")
async def get_complaints(zone: str = None, status: str = "all"):
    """
    Returns complaints for police P9 queue.
    Filter by zone and/or status: valid | invalid | pending | all
    """
    from main import supabase

    try:
        query = (
            supabase.table("complaints")
            .select("*")
            .order("submitted_at", desc=True)
            .limit(50)
        )
        if zone:
            query = query.eq("zone", zone)
        if status and status != "all":
            query = query.eq("status", status)

        result = query.execute()
        return {"complaints": result.data or [], "count": len(result.data or [])}

    except Exception as e:
        logger.error(f"GET /api/complaints error: {e}")
        return JSONResponse(
            status_code=503,
            content={"error": "Database temporarily unavailable", "detail": str(e)},
        )
