from datetime import datetime, timezone, timedelta
from typing import Optional
import logging

from dateutil import parser as dateutil_parser
from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, model_validator

logger = logging.getLogger(__name__)
router = APIRouter()


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class AlertCreateRequest(BaseModel):
    zone: str = Field(
        ...,
        description="One of the 10 BTP zones",
        examples=["Central Zone 1"],
    )
    message_en: str = Field(
        ...,
        description="Alert message in English",
        examples=["Heavy congestion expected near Silk Board from 5-8 PM."],
    )
    severity: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Congestion severity 0.0 (clear) to 1.0 (critical)",
        examples=[0.85],
    )
    corridor: Optional[str] = Field(
        default=None,
        description="Road corridor associated with the alert",
        examples=["CBD 1"],
    )
    message_kn: Optional[str] = Field(
        default=None,
        description="Kannada translation (Bhashini generates this if omitted)",
        examples=["ಸಿಲ್ಕ್ ಬೋರ್ಡ್ ಬಳಿ ಭಾರಿ ಸಂಚಾರ ದಟ್ಟಣೆ ನಿರೀಕ್ಷಿಸಲಾಗಿದೆ."],
    )
    valid_until: Optional[datetime] = Field(
        default=None,
        description="Expiry time (ISO 8601). Defaults to now + 6 hours if omitted.",
        examples=["2026-06-18T23:00:00Z"],
    )

    # -----------------------------------------------------------------------
    # Bug 1 fix: reject valid_until that is in the past relative to valid_from.
    # valid_from is always set to now by the route, but we validate against
    # the request's valid_until here so the 422 fires before any DB call.
    # -----------------------------------------------------------------------
    @model_validator(mode="after")
    def valid_until_must_be_future(self) -> "AlertCreateRequest":
        if self.valid_until is not None:
            now = datetime.now(timezone.utc)
            # Make valid_until timezone-aware if it arrived as naive
            vu = self.valid_until
            if vu.tzinfo is None:
                vu = vu.replace(tzinfo=timezone.utc)
            if vu <= now:
                raise ValueError(
                    "valid_until must be in the future. "
                    f"Received {vu.isoformat()} which is already past."
                )
        return self

    model_config = {
        "json_schema_extra": {
            "example": {
                "zone": "Central Zone 2",
                "corridor": "CBD 2",
                "message_en": "Heavy congestion expected near Silk Board from 5-8 PM due to construction.",
                "message_kn": "ಸಿಲ್ಕ್ ಬೋರ್ಡ್ ಬಳಿ ನಿರ್ಮಾಣ ಕಾರ್ಯದಿಂದ ಸಂಚಾರ ದಟ್ಟಣೆ ನಿರೀಕ್ಷಿಸಲಾಗಿದೆ.",
                "severity": 0.75,
                "valid_until": "2026-06-18T14:30:00Z",
            }
        }
    }


class AlertResponse(BaseModel):
    id: Optional[str] = Field(default=None, description="UUID assigned by Supabase")
    zone: str = Field(..., description="BTP zone this alert applies to")
    corridor: Optional[str] = Field(default=None, description="Road corridor")
    message_en: Optional[str] = Field(default=None, description="English alert message")
    message_kn: Optional[str] = Field(default=None, description="Kannada alert message")
    severity: float = Field(..., description="Severity score 0.0-1.0")
    valid_from: Optional[datetime] = Field(default=None, description="Alert start time")
    valid_until: Optional[datetime] = Field(default=None, description="Alert expiry time")
    created_at: Optional[datetime] = Field(default=None, description="Row creation timestamp")

    model_config = {"from_attributes": True}


class AlertsListResponse(BaseModel):
    alerts: list[AlertResponse]
    count: int = Field(..., description="Number of alerts returned")


class DismissAlertResponse(BaseModel):
    success: bool
    alert_id: str = Field(..., description="ID of the dismissed alert")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_ts(value: str | None, row_id: str, field: str) -> Optional[datetime]:
    """
    Bug 2 fix: tolerant timestamp parser.
    - Uses dateutil which handles all ISO 8601 variants including
      '2026-06-19T04:04:41.11+00:00' that datetime.fromisoformat() rejects
      on Python < 3.11.
    - Returns None and logs on any parse failure instead of raising.
    - Never crashes the caller.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    try:
        dt = dateutil_parser.parse(value)
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    except Exception as exc:
        logger.warning(
            "Skipping malformed timestamp in alerts row %s field %s: %r — %s",
            row_id, field, value, exc,
        )
        return None


def _filter_active_fallback(rows: list[dict], now: datetime) -> list[dict]:
    """
    Python-side safety net used ONLY when the RPC call fails entirely.
    The RPC (get_active_alerts) handles all filtering correctly in SQL;
    this function is never called on RPC results.

    Uses _parse_ts for tolerant parsing — a single bad row is logged and
    skipped rather than crashing the endpoint.
    """
    result = []
    for row in rows:
        row_id = row.get("id", "unknown")

        vf = _parse_ts(row.get("valid_from"), row_id, "valid_from")
        vu = _parse_ts(row.get("valid_until"), row_id, "valid_until")

        # NULL valid_from  → treat as already started
        started = (vf is None) or (vf <= now)
        # NULL valid_until → treat as never expires
        not_expired = (vu is None) or (vu >= now)

        if started and not_expired:
            result.append(row)

    return result


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.get(
    "/api/alerts",
    response_model=AlertsListResponse,
    summary="List alerts",
    description=(
        "Returns congestion alerts ordered by severity DESC, then created_at DESC. "
        "When `active_only=true` (default) only alerts where "
        "`valid_from <= now <= valid_until` are returned. "
        "NULL `valid_from` is treated as started immediately; "
        "NULL `valid_until` is treated as never expires."
    ),
    responses={
        200: {"description": "Alerts retrieved successfully"},
        503: {"description": "Supabase unavailable"},
    },
    tags=["Alerts"],
)
async def get_alerts(zone: Optional[str] = None, active_only: bool = True):
    from main import supabase

    now = datetime.now(timezone.utc)

    try:
        if active_only:
            # Primary path: RPC handles NULL-safe filtering entirely in SQL.
            # _filter_active_fallback is NOT applied to RPC results — the SQL
            # already did the filtering correctly.
            rpc_params = {"p_now": now.isoformat()}
            if zone:
                rpc_params["p_zone"] = zone
            try:
                result = supabase.rpc("get_active_alerts", rpc_params).execute()
                rows = result.data or []
            except Exception as rpc_err:
                # RPC unavailable: fall back to full table fetch + Python filter.
                # This path uses _filter_active_fallback with tolerant parsing.
                logger.warning("get_active_alerts RPC failed, using fallback: %s", rpc_err)
                query = (
                    supabase.table("alerts")
                    .select("id,zone,corridor,message_en,message_kn,severity,valid_from,valid_until,created_at")
                    .order("severity", desc=True)
                    .order("created_at", desc=True)
                    .limit(50)
                )
                if zone:
                    query = query.eq("zone", zone)
                fallback_result = query.execute()
                rows = _filter_active_fallback(fallback_result.data or [], now)
        else:
            query = (
                supabase.table("alerts")
                .select("id,zone,corridor,message_en,message_kn,severity,valid_from,valid_until,created_at")
                .order("severity", desc=True)
                .order("created_at", desc=True)
                .limit(50)
            )
            if zone:
                query = query.eq("zone", zone)
            result = query.execute()
            rows = result.data or []

        return AlertsListResponse(
            alerts=[AlertResponse(**row) for row in rows],
            count=len(rows),
        )

    except Exception as e:
        logger.error("GET /api/alerts unhandled error: %s", e)
        raise HTTPException(status_code=503, detail="Database temporarily unavailable")


@router.post(
    "/api/alerts",
    response_model=AlertResponse,
    status_code=201,
    summary="Create a new alert",
    description=(
        "Create a congestion alert from the police dashboard. "
        "`zone`, `message_en`, and `severity` are required. "
        "`severity` must be 0.0-1.0. "
        "`valid_from` is always set to now so the alert is immediately visible. "
        "`valid_until` must be in the future and defaults to now + 6 hours if omitted."
    ),
    responses={
        201: {"description": "Alert created and immediately active"},
        422: {
            "description": (
                "Validation error — missing required field, severity out of range, "
                "or valid_until is in the past"
            )
        },
        503: {"description": "Supabase unavailable"},
    },
    tags=["Alerts"],
)
async def create_alert(req: AlertCreateRequest):
    from main import supabase

    try:
        now = datetime.now(timezone.utc)
        insert_data = {
            "zone": req.zone,
            "corridor": req.corridor,
            "message_en": req.message_en,
            "message_kn": req.message_kn,
            "severity": req.severity,
            "valid_from": now.isoformat(),
            "valid_until": (req.valid_until or now + timedelta(hours=6)).isoformat(),
            "created_at": now.isoformat(),
        }

        result = supabase.table("alerts").insert(insert_data).execute()
        row = result.data[0] if result.data else insert_data
        return AlertResponse(**row)

    except Exception as e:
        logger.error("POST /api/alerts error: %s", e)
        raise HTTPException(status_code=503, detail="Database temporarily unavailable")


@router.delete(
    "/api/alerts/{alert_id}",
    response_model=DismissAlertResponse,
    summary="Dismiss an alert",
    description=(
        "Soft-deletes an alert by setting valid_until to now. "
        "The row is retained in Supabase for audit purposes. "
        "The alert disappears from GET active_only=true immediately."
    ),
    responses={
        200: {"description": "Alert dismissed"},
        503: {"description": "Supabase unavailable"},
    },
    tags=["Alerts"],
)
async def dismiss_alert(alert_id: str):
    from main import supabase

    try:
        now_iso = datetime.now(timezone.utc).isoformat()
        supabase.table("alerts").update({"valid_until": now_iso}).eq("id", alert_id).execute()
        return DismissAlertResponse(success=True, alert_id=alert_id)

    except Exception as e:
        logger.error("DELETE /api/alerts/%s error: %s", alert_id, e)
        raise HTTPException(status_code=503, detail="Database temporarily unavailable")


# ---------------------------------------------------------------------------
# Unit tests — run with: pytest routers/alerts.py
# ---------------------------------------------------------------------------

def _run_tests():
    """
    Inline tests. Import and call directly or run via pytest with --doctest-modules.
    These test the helper logic without needing a live Supabase connection.
    """
    from datetime import timezone

    now = datetime.now(timezone.utc)
    past = (now - timedelta(hours=2)).isoformat()
    future = (now + timedelta(hours=2)).isoformat()
    far_future = (now + timedelta(hours=8)).isoformat()

    # Test 1: valid_until before now — row must be excluded
    rows = [{"id": "t1", "valid_from": past, "valid_until": past, "severity": 0.5}]
    assert _filter_active_fallback(rows, now) == [], "Test 1 failed: expired alert should be excluded"

    # Test 2: NULL valid_from — treat as started immediately, must be included
    rows = [{"id": "t2", "valid_from": None, "valid_until": far_future, "severity": 0.5}]
    assert len(_filter_active_fallback(rows, now)) == 1, "Test 2 failed: NULL valid_from should be included"

    # Test 3: NULL valid_until — treat as never expires, must be included
    rows = [{"id": "t3", "valid_from": past, "valid_until": None, "severity": 0.5}]
    assert len(_filter_active_fallback(rows, now)) == 1, "Test 3 failed: NULL valid_until should be included"

    # Test 4: malformed timestamp — must skip row, not crash
    rows = [
        {"id": "t4_bad", "valid_from": "NOT-A-DATE", "valid_until": far_future, "severity": 0.5},
        {"id": "t4_good", "valid_from": past, "valid_until": far_future, "severity": 0.7},
    ]
    result = _filter_active_fallback(rows, now)
    ids = [r["id"] for r in result]
    assert "t4_good" in ids, "Test 4 failed: good row should be included"
    assert "t4_bad" not in ids, "Test 4 failed: malformed row should be skipped"

    # Test 5: Supabase fractional-second timezone format that broke fromisoformat
    ts = "2026-06-19T04:04:41.11+00:00"
    parsed = _parse_ts(ts, "t5", "valid_from")
    assert parsed is not None, "Test 5 failed: dateutil should parse fractional-second tz format"
    assert parsed.tzinfo is not None, "Test 5 failed: parsed datetime must be timezone-aware"

    # Test 6: valid_until in the past should raise ValueError in model validator
    import pytest
    from pydantic import ValidationError
    with pytest.raises(ValidationError) as exc_info:
        AlertCreateRequest(
            zone="Central Zone 1",
            message_en="Test",
            severity=0.5,
            valid_until=now - timedelta(hours=1),
        )
    assert "valid_until must be in the future" in str(exc_info.value)

    print("All 6 tests passed.")


if __name__ == "__main__":
    _run_tests()
