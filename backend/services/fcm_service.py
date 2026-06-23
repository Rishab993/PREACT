"""
Firebase Cloud Messaging (FCM) service for push notifications.
"""
import os
import logging
import httpx

logger = logging.getLogger(__name__)

FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")
FCM_URL = "https://fcm.googleapis.com/fcm/send"


async def send_fcm_notification(
    token: str,
    title: str,
    body: str,
    data: dict = None,
) -> bool:
    """
    Send a push notification via FCM legacy HTTP API.
    Returns True on success, False on failure.
    """
    if not FCM_SERVER_KEY:
        logger.warning("FCM_SERVER_KEY not set — skipping push notification")
        return False

    if not token:
        logger.warning("No FCM token provided — skipping notification")
        return False

    try:
        payload = {
            "to": token,
            "notification": {
                "title": title,
                "body": body,
                "sound": "default",
            },
            "priority": "high",
        }
        if data:
            payload["data"] = data

        headers = {
            "Authorization": f"key={FCM_SERVER_KEY}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(FCM_URL, headers=headers, json=payload)
            response.raise_for_status()
            result = response.json()
            if result.get("success", 0) == 1:
                logger.info(f"FCM notification sent successfully to {token[:20]}...")
                return True
            else:
                logger.error(f"FCM returned failure: {result}")
                return False

    except httpx.HTTPStatusError as e:
        logger.error(f"FCM HTTP error {e.response.status_code}: {e.response.text}")
        return False
    except Exception as e:
        logger.error(f"FCM send error: {e}")
        return False


async def send_fcm_to_multiple(
    tokens: list[str],
    title: str,
    body: str,
    data: dict = None,
) -> dict:
    """
    Send FCM notification to multiple device tokens.
    Returns summary: {sent: int, failed: int}
    """
    if not FCM_SERVER_KEY:
        logger.warning("FCM_SERVER_KEY not set — skipping bulk notifications")
        return {"sent": 0, "failed": len(tokens)}

    if not tokens:
        return {"sent": 0, "failed": 0}

    try:
        payload = {
            "registration_ids": tokens,
            "notification": {
                "title": title,
                "body": body,
                "sound": "default",
            },
            "priority": "high",
        }
        if data:
            payload["data"] = data

        headers = {
            "Authorization": f"key={FCM_SERVER_KEY}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(FCM_URL, headers=headers, json=payload)
            response.raise_for_status()
            result = response.json()
            return {
                "sent": result.get("success", 0),
                "failed": result.get("failure", 0),
            }

    except Exception as e:
        logger.error(f"FCM bulk send error: {e}")
        return {"sent": 0, "failed": len(tokens)}
