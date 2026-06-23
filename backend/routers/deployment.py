from fastapi import APIRouter
from fastapi.responses import JSONResponse
from models.schemas import DeployRequest
import logging

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/deploy")
async def generate_deployment(req: DeployRequest):
    """
    Generate CP-SAT optimal officer deployment plan for an event.
    Returns officer→junction assignments with priority labels.
    Timeout: 2s (OR-Tools solver hard limit).
    """
    from main import supabase
    from services.ortools_service import generate_deployment_plan
    from datetime import datetime, timezone

    try:
        # ── Fetch event ────────────────────────────────────────────────────────
        from fastapi import HTTPException
        event_result = (
            supabase.table("events")
            .select("id,start_dt,end_dt,zone,expected_attendance,corridor")
            .eq("id", req.event_id)
            .execute()
        )
        if not event_result.data:
            raise HTTPException(
                status_code=404,
                detail=f"Event {req.event_id} not found"
            )
        event_data = event_result.data[0]

        # Map end_dt to end_datetime for OR-Tools / output schema consistency
        event_data["end_datetime"] = event_data.get("end_dt")

        # ── Fetch available officers ───────────────────────────────────────────
        officers_query = (
            supabase.table("officers")
            .select("id,badge_number,name,zone,shift_start,shift_end,available")
        )
        if req.available_officer_ids:
            officers_query = officers_query.in_("id", req.available_officer_ids)

        officers_result = officers_query.execute()
        officers = officers_result.data or []

        if not officers:
            raise HTTPException(
                status_code=404,
                detail="No valid officers found"
            )

        # ── Fetch junctions with severity from forecasts ───────────────────────
        fc_result = (
            supabase.table("forecasts")
            .select("corridor,severity")
            .order("severity", desc=True)
            .limit(20)
            .execute()
        )
        forecast_rows = fc_result.data or []

        logger.warning(f"FORECAST ROWS COUNT = {len(forecast_rows)}")

        for row in forecast_rows[:20]:
            logger.warning(
                f"corridor={row.get('corridor')} severity={row.get('severity')}"
            )

        # Build junctions list from top corridors in forecast

        # Normalize corridor name spelling variants before coordinate lookup.
        # Original name is preserved in junction["name"] for API responses.
        CORRIDOR_ALIASES = {
            "Bannerghata Road": "Bannerghatta Road",
            "Bannerghatta Road": "Bannerghatta Road",
            "ORR East": "ORR East 1",
            "ORR North": "ORR North 1",
            "Bellary Road": "Bellary Road 1",
            "IRR Thanisandra Road": "IRR(Thanisandra road)",
            "IRR(Thanisandra Road)": "IRR(Thanisandra road)",
        }

        CORRIDOR_COORDS = {
            "CBD 1": {"lat": 12.9716, "lng": 77.5946},
            "CBD 2": {"lat": 12.9763, "lng": 77.5929},
            "Mysore Road": {"lat": 12.9399, "lng": 77.5527},
            "Tumkur Road": {"lat": 13.0100, "lng": 77.5490},
            "Bellary Road 1": {"lat": 13.0350, "lng": 77.5971},
            "Bellary Road 2": {"lat": 13.0500, "lng": 77.5971},
            "Hosur Road": {"lat": 12.8950, "lng": 77.6350},
            "Bannerghatta Road": {"lat": 12.8700, "lng": 77.5950},
            "ORR East 1": {"lat": 12.9600, "lng": 77.7000},
            "ORR East 2": {"lat": 12.9400, "lng": 77.6900},
            "ORR North 1": {"lat": 13.0200, "lng": 77.6400},
            "ORR North 2": {"lat": 13.0350, "lng": 77.6600},
            "Magadi Road": {"lat": 12.9740, "lng": 77.5300},
            "Old Madras Road": {"lat": 13.0000, "lng": 77.6600},
            "West of Chord Road": {"lat": 13.0150, "lng": 77.5400},
            "Old Airport Road": {"lat": 12.9600, "lng": 77.6400},
            "Varthur Road": {"lat": 12.9400, "lng": 77.7200},
            "Hennur Main Road": {"lat": 13.0400, "lng": 77.6300},
            "IRR(Thanisandra road)": {"lat": 13.0600, "lng": 77.6150},
            "Airport New South Road": {"lat": 13.1800, "lng": 77.6000},
        }

        # Group by corridor, keeping highest severity per corridor
        corridor_max = {}
        for row in forecast_rows:
            corridor = row.get("corridor", "CBD 1")
            sev = float(row.get("severity") or 0.5)
            if corridor not in corridor_max:
                corridor_max[corridor] = sev
            else:
                corridor_max[corridor] = max(corridor_max[corridor], sev)

        junctions = []
        for corridor, sev in corridor_max.items():
            normalized = CORRIDOR_ALIASES.get(corridor, corridor)
            coords = CORRIDOR_COORDS.get(normalized, {"lat": 12.9716, "lng": 77.5946})
            junctions.append({
                "name": corridor,          # preserve original name in API response
                "lat": coords["lat"],
                "lng": coords["lng"],
                "severity": sev,
            })

        logger.warning(f"DEPLOYMENT JUNCTION COUNT = {len(junctions)}")

        # Fallback: use event corridor if no forecast junctions
        if not junctions:
            event_corridor = event_data.get("corridor", "CBD 1")
            coords = CORRIDOR_COORDS.get(event_corridor, {"lat": 12.9716, "lng": 77.5946})
            junctions = [{"name": event_corridor, "lat": coords["lat"], "lng": coords["lng"], "severity": 0.5}]

        # ── Run CP-SAT solver ─────────────────────────────────────────────────
        plan = generate_deployment_plan(officers, junctions, event_data)

        # ── Persist to deployments table ───────────────────────────────────────
        now_iso = datetime.now(timezone.utc).isoformat()
        for item in plan:
            try:
                supabase.table("deployments").insert({
                    "event_id": req.event_id,
                    "officer_id": item["officer_id"],
                    "junction": item["junction"],
                    "lat": item["lat"],
                    "lng": item["lng"],
                    "start_time": item["start_time"],
                    "end_time": item["end_time"],
                    "priority": item["priority"],
                    "source": "preact",
                    "created_at": now_iso,
                }).execute()
            except Exception as db_e:
                logger.warning(f"Could not persist deployment item: {db_e}")

        return {
            "event_id": req.event_id,
            "plan": plan,
            "officer_count": len(plan),
            "junction_count": len(junctions),
        }

    except Exception as e:
        logger.error(f"POST /api/deploy error: {e}")
        return JSONResponse(
            status_code=500,
            content={"error": "Deployment generation failed", "detail": str(e)},
        )