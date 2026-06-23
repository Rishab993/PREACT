"""
APScheduler background job definitions.
Three jobs:
  - Forecast pipeline: every 6h (first run 2 min after startup)
  - Anomaly check: every 30 min
  - Post-event officer nudge: every 15 min
"""
import logging
from datetime import datetime, timedelta

from apscheduler.schedulers.background import BackgroundScheduler

logger = logging.getLogger(__name__)


def init_scheduler(supabase_client) -> BackgroundScheduler:
    scheduler = BackgroundScheduler(timezone="Asia/Kolkata")

    # ── Forecast pipeline — every 6h ─────────────────────────────────────────
    scheduler.add_job(
        func=lambda: _run_forecast(supabase_client),
        trigger="interval",
        hours=6,
        id="forecast",
        max_instances=1,
        next_run_time=datetime.now() + timedelta(minutes=2),
        replace_existing=True,
    )

    # ── Anomaly detection — every 30 min ─────────────────────────────────────
    scheduler.add_job(
        func=lambda: _run_anomaly(supabase_client),
        trigger="interval",
        minutes=30,
        id="anomaly",
        max_instances=1,
        replace_existing=True,
    )

    # ── Post-event officer nudge — every 15 min ───────────────────────────────
    scheduler.add_job(
        func=lambda: notify_post_event_officers(supabase_client),
        trigger="interval",
        minutes=15,
        id="gt_nudge",
        max_instances=1,
        replace_existing=True,
    )

    scheduler.start()
    logger.info("APScheduler started — forecast(6h), anomaly(30min), gt_nudge(15min)")
    return scheduler


def _run_forecast(supabase_client) -> None:
    """Wrapper to catch errors so scheduler never crashes."""
    try:
        from services.forecast_service import run_forecast_pipeline
        logger.info("[Scheduler] Running forecast pipeline...")
        run_forecast_pipeline(supabase_client)
    except Exception as e:
        logger.error(f"[Scheduler] Forecast pipeline error: {e}")


def _run_anomaly(supabase_client) -> None:
    """Wrapper for async anomaly check — run in sync context via asyncio."""
    import asyncio
    try:
        from services.anomaly_service import run_anomaly_check
        logger.info("[Scheduler] Running anomaly check...")
        asyncio.run(run_anomaly_check(supabase_client))
    except RuntimeError:
        # If an event loop is already running, use a new thread
        import threading
        import asyncio as _asyncio

        def _run():
            loop = _asyncio.new_event_loop()
            _asyncio.set_event_loop(loop)
            try:
                from services.anomaly_service import run_anomaly_check
                loop.run_until_complete(run_anomaly_check(supabase_client))
            finally:
                loop.close()

        t = threading.Thread(target=_run, daemon=True)
        t.start()
    except Exception as e:
        logger.error(f"[Scheduler] Anomaly check error: {e}")


def notify_post_event_officers(supabase_client) -> None:
    """
    Check if any events ended in the last 15 minutes.
    Send FCM push to assigned officers asking them to submit ground truth.
    """
    import asyncio

    async def _notify():
        try:
            from services.fcm_service import send_fcm_to_multiple
            from datetime import timezone

            now = datetime.now(timezone.utc)
            window_start = (now - timedelta(minutes=15)).isoformat()
            window_end = now.isoformat()

            # Find events that just ended
            events_result = (
                supabase_client.table("events")
                .select("id,end_dt,closed_dt,zone,corridor")
                .or_(
                    f"end_dt.gte.{window_start},end_dt.lte.{window_end},"
                    f"closed_dt.gte.{window_start},closed_dt.lte.{window_end}"
                )
                .execute()
            )
            ended_events = events_result.data or []

            if not ended_events:
                return

            for event in ended_events:
                event_id = event.get("id")
                try:
                    # Find officer IDs from deployments
                    deploy_result = (
                        supabase_client.table("deployments")
                        .select("officer_id")
                        .eq("event_id", event_id)
                        .execute()
                    )
                    officer_ids = [r["officer_id"] for r in (deploy_result.data or [])]

                    if not officer_ids:
                        continue

                    # Fetch FCM tokens for these officers
                    tokens_result = (
                        supabase_client.table("officers")
                        .select("fcm_token")
                        .in_("id", officer_ids)
                        .execute()
                    )
                    tokens = [
                        r["fcm_token"]
                        for r in (tokens_result.data or [])
                        if r.get("fcm_token")
                    ]

                    if tokens:
                        await send_fcm_to_multiple(
                            tokens=tokens,
                            title="Submit Post-Event Report 📋",
                            body="Event ended. Submit your observations in PREACT to improve future deployments.",
                            data={"type": "ground_truth_nudge", "event_id": event_id},
                        )
                        logger.info(
                            f"[Scheduler] Sent GT nudge to {len(tokens)} officers for event {event_id}"
                        )
                except Exception as event_e:
                    logger.warning(f"[Scheduler] GT nudge error for event {event_id}: {event_e}")

        except Exception as e:
            logger.error(f"[Scheduler] notify_post_event_officers error: {e}")

    try:
        asyncio.run(_notify())
    except RuntimeError:
        import threading

        def _run():
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                loop.run_until_complete(_notify())
            finally:
                loop.close()

        t = threading.Thread(target=_run, daemon=True)
        t.start()
