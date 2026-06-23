"""
Non-blocking XGBoost retrain service triggered every 50 ground-truth submissions.
Uploads updated model to Supabase Storage: models/xgb_latest.pkl
"""
import logging
import pickle
from datetime import datetime, timezone

logger = logging.getLogger(__name__)


async def retrain_xgboost(supabase_client) -> None:
    """
    Non-blocking background task — called from FastAPI BackgroundTasks.
    1. Pull events + ground_truth joined data
    2. Build expanded training set
    3. Refit XGBoost
    4. Upload to Supabase Storage
    5. Update module-level xgb_model reference
    """
    import xgboost as xgb
    import pandas as pd
    import numpy as np
    from services.forecast_service import _encode_cause
    import services.forecast_service as fc_svc

    logger.info("Starting XGBoost retrain...")

    try:
        # ── 1. Pull data ───────────────────────────────────────────────────────
        events_result = (
            supabase_client.table("events")
            .select("id,severity_proxy,start_dt,event_cause,zone,corridor")
            .neq("severity_proxy", None)
            .neq("start_dt", None)
            .execute()
        )
        events_rows = events_result.data or []

        gt_result = (
            supabase_client.table("officer_ground_truth")
            .select("event_id,actual_crowd_size,junction_stress")
            .execute()
        )
        gt_rows = gt_result.data or []

        if len(events_rows) < 20:
            logger.warning("Not enough data for retrain — aborting")
            return

        # Build ground truth lookup: event_id -> avg stress
        gt_stress_map: dict[str, float] = {}
        for gt in gt_rows:
            eid = gt.get("event_id", "")
            stress_list = gt.get("junction_stress") or []
            if stress_list:
                try:
                    avg_stress = sum(j.get("stress_level", 3) for j in stress_list) / len(stress_list)
                    gt_stress_map[eid] = avg_stress / 5.0  # normalise to 0-1
                except Exception:
                    pass

        # ── 2. Build feature matrix ────────────────────────────────────────────
        encoder_map: dict[str, int] = {}
        cause_set = list({r.get("event_cause", "Other") for r in events_rows})
        encoder_map = {v: i for i, v in enumerate(cause_set)}

        X_rows, y_rows = [], []
        for row in events_rows:
            eid = row.get("id", "")
            try:
                sev = float(row.get("severity_proxy") or 0.5)
                dt_str = row.get("start_dt", "")
                hour_of_day, day_of_week = 12, 1
                if dt_str:
                    dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00"))
                    hour_of_day = dt.hour
                    day_of_week = dt.weekday()
                cause_enc = encoder_map.get(row.get("event_cause", "Other"), 0)
                # Use ground truth stress as target if available, else severity_proxy
                target = gt_stress_map.get(eid, sev)
                X_rows.append([sev, hour_of_day, day_of_week, cause_enc])
                y_rows.append(target)
            except Exception as row_e:
                logger.debug(f"Row skip in retrain: {row_e}")
                continue

        if len(X_rows) < 20:
            logger.warning("Not enough valid training rows — aborting retrain")
            return

        X_train = np.array(X_rows)
        y_raw = np.array(y_rows)

        # Convert continuous target to tier labels (0-3)
        def to_tier(v: float) -> int:
            if v < 0.35:
                return 0
            elif v < 0.6:
                return 1
            elif v < 0.8:
                return 2
            return 3

        y_train = np.array([to_tier(v) for v in y_raw])

        # ── 3. Fit XGBoost ─────────────────────────────────────────────────────
        model = xgb.XGBClassifier(
            n_estimators=150,
            max_depth=5,
            learning_rate=0.08,
            use_label_encoder=False,
            eval_metric="mlogloss",
            verbosity=0,
        )
        model.fit(X_train, y_train)
        logger.info(f"XGBoost retrained on {len(X_rows)} rows")

        # ── 4. Serialize + upload to Supabase Storage ──────────────────────────
        model_bytes = pickle.dumps(model)
        try:
            supabase_client.storage.from_("models").upload(
                "xgb_latest.pkl",
                model_bytes,
                {"content-type": "application/octet-stream", "upsert": "true"},
            )
            logger.info("xgb_latest.pkl uploaded to Supabase Storage")
        except Exception as upload_e:
            logger.error(f"Model upload failed: {upload_e}")

        # ── 5. Update module-level reference ───────────────────────────────────
        fc_svc.xgb_model = model
        fc_svc._xgb_label_encoder = encoder_map

        logger.info(
            f"Retrain complete — rows_used={len(X_rows)}, "
            f"timestamp={datetime.now(timezone.utc).isoformat()}"
        )

    except Exception as e:
        logger.error(f"XGBoost retrain failed: {e}")
