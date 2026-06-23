"""
Prophet + XGBoost forecast pipeline.
Prophet: lazy import (only when forecast runs, ~80MB).
XGBoost: loaded on first call, stays in memory (~30MB).
"""
import logging
import pickle
from datetime import datetime, timezone, timedelta
from typing import Optional, Any

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# Module-level model — populated on first call, stays loaded
xgb_model: Optional[Any] = None
_xgb_label_encoder: Optional[Any] = None  # for event_cause encoding

SEVERITY_TIERS = {
    "LOW": (0.0, 0.35),
    "MEDIUM": (0.35, 0.6),
    "HIGH": (0.6, 0.8),
    "CRITICAL": (0.8, 1.01),
}


def _severity_to_tier(s: float) -> str:
    if s < 0.35:
        return "LOW"
    elif s < 0.6:
        return "MEDIUM"
    elif s < 0.8:
        return "HIGH"
    return "CRITICAL"


def _encode_cause(cause: str, encoder_map: dict) -> int:
    return encoder_map.get(str(cause).strip(), 0)


def _fit_xgb(df: pd.DataFrame) -> tuple:
    """Fit XGBoost severity tier classifier on events DataFrame."""
    import xgboost as xgb

    causes = df["event_cause"].fillna("Unknown").astype(str).str.strip()
    unique_causes = causes.unique().tolist()
    encoder_map = {v: i for i, v in enumerate(unique_causes)}

    df = df.copy()
    df["hour_of_day"] = pd.to_datetime(df["start_dt"], utc=True, errors="coerce").dt.hour.fillna(12)
    df["day_of_week"] = pd.to_datetime(df["start_dt"], utc=True, errors="coerce").dt.dayofweek.fillna(0)
    df["cause_enc"] = causes.map(encoder_map).fillna(0)
    df["tier_label"] = df["severity_proxy"].apply(_severity_to_tier)
    tier_map = {"LOW": 0, "MEDIUM": 1, "HIGH": 2, "CRITICAL": 3}
    df["tier_int"] = df["tier_label"].map(tier_map)

    feature_cols = ["severity_proxy", "hour_of_day", "day_of_week", "cause_enc"]
    X = df[feature_cols].fillna(0).values
    y = df["tier_int"].fillna(0).astype(int).values

    model = xgb.XGBClassifier(
        n_estimators=100,
        max_depth=4,
        learning_rate=0.1,
        use_label_encoder=False,
        eval_metric="mlogloss",
        verbosity=0,
    )
    model.fit(X, y)
    return model, encoder_map


def run_forecast_pipeline(supabase_client) -> None:
    """
    Called by APScheduler every 6h and by POST /api/forecast.
    Prophet is lazy-imported here (not at module level) to save RAM at startup.
    """
    global xgb_model, _xgb_label_encoder

    try:
        from prophet import Prophet  # lazy import — ~80MB

        logger.info("Starting forecast pipeline...")

        # 1. Pull training data
        result = (
            supabase_client.table("events")
            .select("start_dt,severity_proxy,zone,corridor,event_cause")
            .neq("severity_proxy", None)
            .neq("start_dt", None)
            .execute()
        )
        rows = result.data or []
        if not rows:
            logger.warning("No events data found for forecast pipeline")
            return

        df = pd.DataFrame(rows)
        df["start_dt"] = pd.to_datetime(df["start_dt"], utc=True, errors="coerce")
        df["severity_proxy"] = pd.to_numeric(df["severity_proxy"], errors="coerce")
        df = df.dropna(subset=["start_dt", "severity_proxy"])
        df["hour_of_day"] = df["start_dt"].dt.hour
        df["day_of_week"] = df["start_dt"].dt.dayofweek

        # 2. Fit XGBoost if not loaded
        if xgb_model is None:
            logger.info("Fitting XGBoost classifier...")
            try:
                xgb_model, _xgb_label_encoder = _fit_xgb(df)
                logger.info("XGBoost fitted successfully")
            except Exception as xgb_e:
                logger.error(f"XGBoost fit failed: {xgb_e}")

        # 3. Determine zone × corridor combos with ≥ 30 data points
        grouped = df.groupby(["zone", "corridor"])
        now_utc = datetime.now(timezone.utc)
        forecast_rows_to_upsert = []

        for (zone, corridor), group in grouped:
            if len(group) < 30:
                logger.debug(f"Skipping {zone}/{corridor}: only {len(group)} rows")
                continue

            try:
                prophet_df = group[["start_dt", "severity_proxy"]].rename(
                    columns={"start_dt": "ds", "severity_proxy": "y"}
                )
                prophet_df["ds"] = prophet_df["ds"].dt.tz_localize(None)
                prophet_df["hour_of_day"] = prophet_df["ds"].dt.hour
                prophet_df["day_of_week"] = prophet_df["ds"].dt.dayofweek

                m = Prophet(
                    yearly_seasonality=False,
                    weekly_seasonality=True,
                    daily_seasonality=True,
                    uncertainty_samples=100,
                )
                m.add_regressor("hour_of_day")
                m.add_regressor("day_of_week")
                m.fit(prophet_df)

                future = m.make_future_dataframe(periods=72, freq="h", include_history=False)
                future["hour_of_day"] = future["ds"].dt.hour
                future["day_of_week"] = future["ds"].dt.dayofweek

                forecast = m.predict(future)

                # Build rows for upsert
                for _, frow in forecast.iterrows():
                    raw_sev = float(np.clip(frow["yhat"], 0.0, 1.0))
                    lower = float(np.clip(frow["yhat_lower"], 0.0, 1.0))
                    upper = float(np.clip(frow["yhat_upper"], 0.0, 1.0))
                    forecast_hour = frow["ds"]

                    # XGBoost tier prediction
                    tier = _severity_to_tier(raw_sev)
                    if xgb_model is not None and _xgb_label_encoder is not None:
                        try:
                            tier_int = int(
                                xgb_model.predict(
                                    [[raw_sev, forecast_hour.hour, forecast_hour.dayofweek, 0]]
                                )[0]
                            )
                            tier = ["LOW", "MEDIUM", "HIGH", "CRITICAL"][tier_int]
                        except Exception:
                            pass

                    forecast_rows_to_upsert.append({
                        "zone": zone,
                        "corridor": corridor,
                        "forecast_hour": forecast_hour.isoformat() + "+00:00",
                        "severity": raw_sev,
                        "confidence_lower": lower,
                        "confidence_upper": upper,
                        "created_at": now_utc.isoformat(),
                    })

            except Exception as prophet_e:
                logger.error(f"Prophet failed for {zone}/{corridor}: {prophet_e}")
                continue

        # 4. UPSERT in batches (avoid duplicates on reschedule)
        if forecast_rows_to_upsert:
            batch_size = 200
            for i in range(0, len(forecast_rows_to_upsert), batch_size):
                batch = forecast_rows_to_upsert[i : i + batch_size]
                try:
                    supabase_client.table("forecasts").upsert(
                        batch,
                        on_conflict="zone,corridor,forecast_hour",
                    ).execute()
                except Exception as upsert_e:
                    logger.error(f"Upsert batch {i} failed: {upsert_e}")

            logger.info(f"Forecast pipeline complete — upserted {len(forecast_rows_to_upsert)} rows")
        else:
            logger.warning("No forecast rows generated")

    except Exception as e:
        logger.error(f"Forecast pipeline error: {e}")


def get_forecast_for_event(event_id: str, supabase_client) -> list:
    """
    On-demand: called by /api/forecast endpoint.
    Checks if forecasts are stale (> 6h old) and triggers pipeline if needed.
    Returns last 72h of forecast rows for this event's zone.
    """
    try:
        # Fetch event details
        event_result = (
            supabase_client.table("events")
            .select("zone,corridor")
            .eq("id", event_id)
            .execute()
        )
        if not event_result.data:
            raise ValueError(f"Event {event_id} not found")

        event_data = event_result.data[0]
        zone = event_data.get("zone")
        corridor = event_data.get("corridor")

        # Check staleness
        stale_threshold = (datetime.now(timezone.utc) - timedelta(hours=6)).isoformat()
        existing = (
            supabase_client.table("forecasts")
            .select("created_at")
            .eq("zone", zone)
            .gt("forecast_hour", datetime.now(timezone.utc).isoformat())
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )

        needs_refresh = True
        if existing.data:
            latest_created = existing.data[0].get("created_at", "")
            if latest_created and latest_created > stale_threshold:
                needs_refresh = False

        if needs_refresh:
            logger.info(f"Forecasts stale/missing for zone={zone} — triggering pipeline")
            run_forecast_pipeline(supabase_client)

        # Return forecast rows
        now = datetime.now(timezone.utc)
        end = (now + timedelta(hours=72)).isoformat()
        query = (
            supabase_client.table("forecasts")
            .select("zone,corridor,forecast_hour,severity,confidence_lower,confidence_upper")
            .eq("zone", zone)
            .gt("forecast_hour", now.isoformat())
            .lt("forecast_hour", end)
            .order("forecast_hour")
        )
        if corridor:
            query = query.eq("corridor", corridor)

        rows_result = query.execute()
        return rows_result.data or []

    except ValueError as val_err:
        raise val_err
    except Exception as e:
        logger.error(f"get_forecast_for_event error: {e}")
        return []
