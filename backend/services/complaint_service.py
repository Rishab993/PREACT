"""
Complaint validation service — GPS plausibility, blur detection, duplicate suppression.
"""
import logging
import math
from typing import Optional

import cv2
import numpy as np

logger = logging.getLogger(__name__)


def _haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Returns distance in metres between two (lat, lng) coordinate pairs."""
    R = 6_371_000  # Earth radius in metres
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def validate_complaint(
    image_bytes: bytes,
    submitted_lat: float,
    submitted_lng: float,
    exif_lat: Optional[float],
    exif_lng: Optional[float],
    zone: str,
    violation_type: str,
    supabase_client,
) -> dict:
    """
    Validates a complaint photo submission with three checks.

    Returns:
        {valid: bool, reason: str | None, confidence_score: float}

    Check 1 — GPS plausibility:
        Haversine distance between submitted and EXIF coordinates.
        PASS if distance < 200m OR EXIF not available (0/null).

    Check 2 — Blur detection via Laplacian variance:
        PASS if variance > 100.

    Check 3 — Duplicate suppression:
        PASS if no identical zone+violation_type in last 30 minutes.
    """
    gps_pass = True
    gps_reason: Optional[str] = None
    blur_pass = True
    blur_reason: Optional[str] = None
    dup_pass = True
    dup_reason: Optional[str] = None

    # ── Check 1: GPS plausibility ──────────────────────────────────────────────
    try:
        if (
            exif_lat is not None
            and exif_lng is not None
            and (abs(exif_lat) > 0.001 or abs(exif_lng) > 0.001)
        ):
            distance_m = _haversine_distance(
                submitted_lat, submitted_lng, exif_lat, exif_lng
            )
            if distance_m >= 200:
                gps_pass = False
                gps_reason = "Location mismatch — submitted location differs from photo GPS"
    except Exception as e:
        logger.warning(f"GPS check error (treating as pass): {e}")

    # ── Check 2: Blur detection ────────────────────────────────────────────────
    try:
        img_array = np.frombuffer(image_bytes, np.uint8)
        img = cv2.imdecode(img_array, cv2.IMREAD_GRAYSCALE)
        if img is None:
            blur_pass = False
            blur_reason = "Could not process image"
        else:
            laplacian_var = cv2.Laplacian(img, cv2.CV_64F).var()
            if laplacian_var <= 100:
                blur_pass = False
                blur_reason = "Image too blurry — please retake in better lighting"
    except Exception as e:
        logger.warning(f"Blur check error: {e}")
        blur_pass = False
        blur_reason = "Could not process image"

    # ── Check 3: Duplicate suppression ────────────────────────────────────────
    try:
        from datetime import datetime, timedelta, timezone
        thirty_minutes_ago = (datetime.now(timezone.utc) - timedelta(minutes=30)).isoformat()
        dup_result = (
            supabase_client.table("complaints")
            .select("id")
            .eq("zone", zone)
            .eq("violation_type", violation_type)
            .gt("submitted_at", thirty_minutes_ago)
            .execute()
        )
        if dup_result.data and len(dup_result.data) > 0:
            dup_pass = False
            dup_reason = "Duplicate report — this incident was already reported in your zone"
    except Exception as e:
        logger.warning(f"Duplicate check error (treating as pass): {e}")

    # ── Compute confidence score ───────────────────────────────────────────────
    confidence_score = 0.0

    if gps_pass:
        confidence_score += 0.35

    if blur_pass:
        confidence_score += 0.35

    if dup_pass:
        confidence_score += 0.20

    if img is not None:
        confidence_score += min(laplacian_var / 1500.0, 0.10)

    confidence_score = min(confidence_score, 1.0)

    # Overall validity: all three checks must pass
    valid = gps_pass and blur_pass and dup_pass

    # First failing reason
    reason: Optional[str] = None
    if not gps_pass:
        reason = gps_reason
    elif not blur_pass:
        reason = blur_reason
    elif not dup_pass:
        reason = dup_reason

    return {
        "valid": valid,
        "reason": reason,
        "confidence_score": round(confidence_score, 2),
    }
