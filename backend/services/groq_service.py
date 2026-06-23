"""
Groq API service: audio transcription (Whisper) + LLM chat (LLaMA 3).
"""
import os
import logging
import httpx

logger = logging.getLogger(__name__)

GROQ_API_KEY = os.getenv("GROQ_API_KEY", "")
GROQ_BASE_URL = "https://api.groq.com/openai/v1"

CITIZEN_SYSTEM_PROMPT = """You are PREACT, a Bengaluru traffic assistant for citizens.
Answer only from the provided data. Be concise (2-3 sentences max).
If asked in Kannada, reply entirely in Kannada.
Do not speculate beyond the data provided."""

POLICE_SYSTEM_PROMPT = """You are PREACT, an operational intelligence assistant for Bengaluru Traffic Police.
Answer only from the provided enforcement database context.
Give specific actionable answers: officer counts, junction names, time windows, severity scores.
If asked in Kannada, reply entirely in Kannada.
Never speculate beyond the data. Cite the source event or junction when giving numbers."""


async def transcribe_audio(audio_bytes: bytes, language: str = "en") -> str:
    """
    Transcribe audio using Groq Whisper large-v3.
    Returns transcribed text string.
    """
    if not GROQ_API_KEY:
        logger.error("GROQ_API_KEY not set")
        return ""

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            files = {
                "file": ("audio.webm", audio_bytes, "audio/webm"),
            }
            data = {
                "model": "whisper-large-v3",
                "language": language,
            }
            headers = {"Authorization": f"Bearer {GROQ_API_KEY}"}

            response = await client.post(
                f"{GROQ_BASE_URL}/audio/transcriptions",
                headers=headers,
                files=files,
                data=data,
            )
            response.raise_for_status()
            result = response.json()
            return result.get("text", "")

    except httpx.HTTPStatusError as e:
        logger.error(f"Groq transcription HTTP error {e.response.status_code}: {e.response.text}")
        return ""
    except Exception as e:
        logger.error(f"Groq transcription error: {e}")
        return ""


async def generate_answer(question: str, context: str, system_prompt: str) -> str:
    """
    Generate LLM answer using Groq LLaMA 3 8B.
    Returns answer string.
    """
    if not GROQ_API_KEY:
        logger.error("GROQ_API_KEY not set")
        return "Service temporarily unavailable"

    try:
        user_content = question
        if context:
            user_content = f"{question}\n\nData:\n{context}"

        payload = {
            "model": "llama-3.1-8b-instant",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_content},
            ],
            "max_tokens": 512,
            "temperature": 0.3,
        }
        headers = {
            "Authorization": f"Bearer {GROQ_API_KEY}",
            "Content-Type": "application/json",
        }

        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.post(
                f"{GROQ_BASE_URL}/chat/completions",
                headers=headers,
                json=payload,
            )
            response.raise_for_status()
            result = response.json()
            return result["choices"][0]["message"]["content"]

    except httpx.HTTPStatusError as e:
        logger.exception(
            f"Groq chat HTTP error {e.response.status_code}: {e.response.text}"
        )
        return f"Groq HTTP Error: {e.response.status_code}"
    except Exception as e:
        logger.exception(
            f"Groq generate_answer error: {repr(e)}"
        )
        return f"Groq Error: {repr(e)}"
