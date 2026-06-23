"""
Memory search service — full-text search over event debriefs + similar event lookup.
"""
import logging

logger = logging.getLogger(__name__)


async def search_debriefs(
    q: str,
    zone: str = None,
    event_type: str = None,
    min_attendance: int = 0,
    supabase_client=None,
) -> list:
    """
    Full-text search over event_debriefs joined with events.
    Uses PostgreSQL tsvector via Supabase RPC function 'search_debriefs'.

    Falls back to simple client-side filter if RPC is unavailable or returns nothing.
    """
    try:
        # Attempt RPC (requires the SQL function defined in Supabase)
        params = {
            "search_query": q or "",
            "filter_zone": zone,
            "filter_event_type": event_type,
            "filter_min_attendance": min_attendance,
        }
        rpc_result = supabase_client.rpc("search_debriefs", params).execute()
        # Only use RPC result if it returned actual data rows (not empty list)
        if rpc_result.data:
            rows = rpc_result.data
            for r in rows:
                r["preact_estimate"] = r.pop("preact_congestion_estimate", 0.0)
                r["avoided_minutes"] = r.pop("congestion_avoided_minutes", 0.0)
            return rows

    except Exception as rpc_e:
        logger.warning(f"RPC search_debriefs failed — falling back to client-side filter: {rpc_e}")

    # ── Fallback: fetch all rows and filter entirely in Python ─────────────────
    # NOTE: PostgREST join-column filters (e.g. .eq("events.zone", zone)) are
    # unreliable — do ALL filtering client-side after fetching the joined rows.
    try:
        result = (
            supabase_client.table("event_debriefs")
            .select(
                "*, events!inner(event_cause, description, expected_attendance, "
                "location_name, start_dt, zone)"
            )
            .order("regret_score", desc=True)
            .limit(200)
            .execute()
        )
        rows = result.data or []

        # Client-side filters
        if zone:
            rows = [r for r in rows if (r.get("events") or {}).get("zone") == zone]
        if event_type:
            rows = [r for r in rows if (r.get("events") or {}).get("event_cause") == event_type]
        if min_attendance > 0:
            rows = [
                r for r in rows
                if ((r.get("events") or {}).get("expected_attendance") or 0) >= min_attendance
            ]

        # Keyword search across debrief + event fields
        if q:
            q_lower = q.lower()
            filtered = []
            for r in rows:
                ev = r.get("events") or {}
                haystack = " ".join([
                    r.get("notes") or "",
                    r.get("top_intervention") or "",
                    r.get("missed_opportunity") or "",
                    ev.get("event_cause") or "",
                    ev.get("description") or "",
                ])
                if q_lower in haystack.lower():
                    filtered.append(r)
            rows = filtered

        # Map DB column names to response keys
        for r in rows:
            r["preact_estimate"] = r.pop("preact_congestion_estimate", 0.0)
            r["avoided_minutes"] = r.pop("congestion_avoided_minutes", 0.0)

        return rows

    except Exception as e:
        logger.error(f"search_debriefs fallback error: {e}")
        return []



async def find_similar_events(event_id: str, supabase_client) -> list:
    """
    Find top 3 past events with similar zone, cause, and expected attendance (±20%).
    Returns debrief rows ordered by regret_score DESC.
    """
    try:
        # Fetch reference event
        ref_result = (
            supabase_client.table("events")
            .select("zone,event_cause,expected_attendance")
            .eq("id", event_id)
            .execute()
        )
        ref = ref_result.data[0] if ref_result.data else None
        if not ref:
            logger.warning(f"Reference event {event_id} not found")
            return []

        zone = ref.get("zone")
        event_cause = ref.get("event_cause")
        attendance = ref.get("expected_attendance")

        query = (
            supabase_client.table("event_debriefs")
            .select(
                "*, events!inner(event_cause, description, expected_attendance, "
                "location_name, start_dt, zone)"
            )
            .neq("event_id", event_id)
        )
        if zone:
            query = query.eq("events.zone", zone)
        if event_cause:
            query = query.eq("events.event_cause", event_cause)

        result = query.order("regret_score", desc=True).execute()
        rows = result.data or []

        # Filter by attendance (±20%) client-side to handle None values gracefully
        filtered_rows = []
        for r in rows:
            ev = r.get("events") or {}
            ev_att = ev.get("expected_attendance")
            
            ref_val = float(attendance) if attendance is not None else 5000.0
            cmp_val = float(ev_att) if ev_att is not None else 5000.0
            
            if ref_val * 0.8 <= cmp_val <= ref_val * 1.2:
                filtered_rows.append(r)

        rows = filtered_rows[:3]

        for r in rows:
            r["preact_estimate"] = r.pop("preact_congestion_estimate", 0.0)
            r["avoided_minutes"] = r.pop("congestion_avoided_minutes", 0.0)
        return rows

    except Exception as e:
        logger.error(f"find_similar_events error: {e}")
        return []
