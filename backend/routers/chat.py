import logging
from datetime import datetime, timezone

from fastapi import APIRouter, UploadFile, File, Form
from fastapi.responses import JSONResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/api/chat")
async def chat(
    audio: UploadFile = File(...),
    language: str = Form("en"),
    role: str = Form("citizen"),
):
    """
    Voice assistant endpoint.
    1. Transcribe audio via Groq Whisper
    2. Fetch relevant context from Supabase
    3. Generate answer via Groq LLaMA 3
    TTS is handled on-device by flutter_tts — no audio bytes returned.
    """
    from main import supabase
    from services.groq_service import (
        transcribe_audio,
        generate_answer,
        CITIZEN_SYSTEM_PROMPT,
        POLICE_SYSTEM_PROMPT,
    )

    try:
        audio_bytes = await audio.read()

        # ── 1. Transcription ──────────────────────────────────────────────────
        transcript = await transcribe_audio(audio_bytes, language)
        if not transcript:
            return JSONResponse(
                status_code=422,
                content={"error": "Could not transcribe audio", "detail": "Empty transcript"},
            )

        # ── 2. Context fetch + answer ─────────────────────────────────────────
        if role == "police":
            context = await _fetch_police_context(transcript, supabase)
            answer = await generate_answer(transcript, context, POLICE_SYSTEM_PROMPT)
            # Log to police_chat_log
            try:
                supabase.table("police_chat_log").insert({
                    "transcript": transcript,
                    "answer": answer,
                    "language": language,
                    "created_at": datetime.now(timezone.utc).isoformat(),
                }).execute()
            except Exception as log_e:
                logger.warning(f"Could not log police chat: {log_e}")
        else:
            context = await _fetch_citizen_context(transcript, supabase)
            answer = await generate_answer(transcript, context, CITIZEN_SYSTEM_PROMPT)

        return {
            "answer_text": answer,
            "transcript": transcript,
        }

    except Exception as e:
        logger.error(f"POST /api/chat error: {e}")
        return {
            "answer_text": "Service temporarily unavailable",
            "transcript": "",
        }


async def _fetch_citizen_context(question: str, supabase) -> str:
    """Build context string for citizen queries from alerts + forecasts."""
    q_lower = question.lower()
    parts = []

    try:
        if any(k in q_lower for k in ["alert", "congestion", "traffic", "jam", "block"]):
            from datetime import datetime, timezone
            result = (
                supabase.table("alerts")
                .select("zone,corridor,message_en,severity,valid_until")
                .gt("valid_until", datetime.now(timezone.utc).isoformat())
                .order("severity", desc=True)
                .limit(10)
                .execute()
            )
            if result.data:
                parts.append("ACTIVE ALERTS:\n" + _format_rows(result.data))

        if any(k in q_lower for k in ["forecast", "tomorrow", "tonight", "predict", "expect"]):
            from datetime import timedelta
            now = datetime.now(timezone.utc)
            end = (now + timedelta(hours=12)).isoformat()
            result = (
                supabase.table("forecasts")
                .select("zone,corridor,forecast_hour,severity")
                .gt("forecast_hour", now.isoformat())
                .lt("forecast_hour", end)
                .order("severity", desc=True)
                .limit(10)
                .execute()
            )
            if result.data:
                parts.append("FORECASTS (next 12h):\n" + _format_rows(result.data))

        # Default: both tables
        if not parts:
            r1 = supabase.table("alerts").select("zone,message_en,severity").limit(5).execute()
            r2 = (
                supabase.table("forecasts")
                .select("zone,corridor,severity")
                .order("forecast_hour")
                .limit(5)
                .execute()
            )
            if r1.data:
                parts.append("ALERTS:\n" + _format_rows(r1.data))
            if r2.data:
                parts.append("FORECASTS:\n" + _format_rows(r2.data))

    except Exception as e:
        logger.warning(f"Citizen context fetch error: {e}")

    return "\n\n".join(parts) if parts else "No current data available."


async def _fetch_police_context(question: str, supabase) -> str:
    """Build context string for police officer queries from multiple tables."""
    q_lower = question.lower()
    parts = []

    try:
        if any(k in q_lower for k in ["officer", "deploy", "how many", "assignment", "strength"]):
            r = (
                supabase.table("deployments")
                .select("junction,priority,source,officers!inner(name,badge_number,zone)")
                .order("created_at", desc=True)
                .limit(10)
                .execute()
            )
            if r.data:
                parts.append("RECENT DEPLOYMENTS:\n" + _format_rows(r.data))

            r2 = (
                supabase.table("officers")
                .select("name,badge_number,zone,available,shift_start,shift_end")
                .eq("available", True)
                .limit(10)
                .execute()
            )
            if r2.data:
                parts.append("AVAILABLE OFFICERS:\n" + _format_rows(r2.data))

        if any(k in q_lower for k in ["diversion", "intervention", "worked", "strategy", "best"]):
            r = (
                supabase.table("event_debriefs")
                .select("event_id,top_intervention,missed_opportunity,congestion_avoided_minutes,regret_score")
                .order("regret_score", desc=True)
                .limit(5)
                .execute()
            )
            if r.data:
                for row in r.data:
                    row["avoided_minutes"] = row.pop("congestion_avoided_minutes", 0.0)
                parts.append("INTERVENTION HISTORY:\n" + _format_rows(r.data))

        if any(k in q_lower for k in ["stress", "junction", "ground"]):
            r = (
                supabase.table("officer_ground_truth")
                .select("junction_stress,event_id,actual_crowd_size")
                .order("created_at", desc=True)
                .limit(5)
                .execute()
            )
            if r.data:
                parts.append("GROUND TRUTH STRESS:\n" + _format_rows(r.data))

        if any(k in q_lower for k in ["forecast", "tonight", "zone", "severity", "predict"]):
            from datetime import timedelta
            now = datetime.now(timezone.utc)
            end = (now + timedelta(hours=12)).isoformat()
            r = (
                supabase.table("forecasts")
                .select("zone,corridor,forecast_hour,severity")
                .gt("forecast_hour", now.isoformat())
                .lt("forecast_hour", end)
                .order("severity", desc=True)
                .limit(10)
                .execute()
            )
            if r.data:
                parts.append("FORECAST (next 12h):\n" + _format_rows(r.data))

        if any(k in q_lower for k in ["volunteer", "citizen", "help"]):
            r = (
                supabase.table("volunteer_assignments")
                .select("citizen_id,junction,date,start_time,end_time,status")
                .eq("status", "approved")
                .order("date")
                .limit(5)
                .execute()
            )
            if r.data:
                parts.append("UPCOMING VOLUNTEERS:\n" + _format_rows(r.data))

        # Default: forecasts + alerts + debriefs
        if not parts:
            r1 = (
                supabase.table("forecasts")
                .select("zone,severity,corridor")
                .order("severity", desc=True)
                .limit(5)
                .execute()
            )
            r2 = (
                supabase.table("alerts")
                .select("zone,message_en,severity")
                .order("severity", desc=True)
                .limit(5)
                .execute()
            )
            r3 = (
                supabase.table("event_debriefs")
                .select("top_intervention,congestion_avoided_minutes")
                .limit(5)
                .execute()
            )
            if r1.data:
                parts.append("FORECASTS:\n" + _format_rows(r1.data))
            if r2.data:
                parts.append("ALERTS:\n" + _format_rows(r2.data))
            if r3.data:
                for row in r3.data:
                    row["avoided_minutes"] = row.pop("congestion_avoided_minutes", 0.0)
                parts.append("DEBRIEFS:\n" + _format_rows(r3.data))

    except Exception as e:
        logger.warning(f"Police context fetch error: {e}")

    return "\n\n".join(parts) if parts else "No enforcement data available."


def _format_rows(rows: list) -> str:
    """Convert list of dicts to a compact readable string for LLM context."""
    lines = []
    for row in rows:
        line = " | ".join(f"{k}: {v}" for k, v in row.items() if v is not None)
        lines.append(line)
    return "\n".join(lines)
