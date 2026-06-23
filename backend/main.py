"""
PREACT FastAPI Backend — main entry point.
Start with: uvicorn main:app --reload

Startup sequence:
  1. Load .env
  2. Init Supabase client (SERVICE_KEY)
  3. Fit IsolationForest on historical events
  4. Start APScheduler (forecast 6h, anomaly 30min, gt_nudge 15min)
  5. Include all 12 routers
"""
import os
import logging
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from supabase import create_client, Client

# ── Load environment variables ───────────────────────────────────────────────
load_dotenv()

# ── Logging configuration ────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)
logger = logging.getLogger(__name__)

# ── Supabase client — single instance, imported by all routers/services ──────
SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY: str = os.getenv("SUPABASE_SERVICE_KEY", "")

if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    logger.warning(
        "SUPABASE_URL or SUPABASE_SERVICE_KEY not set — "
        "DB calls will fail. Check your .env file."
    )

supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# ── Scheduler reference (set during startup) ─────────────────────────────────
_scheduler = None


# ── Lifespan: startup + shutdown ─────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    global _scheduler

    logger.info("=== PREACT Backend starting up ===")

    # 1. Fit IsolationForest (~20MB, blocking but fast)
    try:
        from services.anomaly_service import fit_on_startup
        logger.info("Fitting IsolationForest on historical events...")
        fit_on_startup(supabase)
        logger.info("IsolationForest ready")
    except Exception as e:
        logger.error(f"IsolationForest startup fit failed (non-fatal): {e}")

    # 2. Start APScheduler
    try:
        from scheduler import init_scheduler
        _scheduler = init_scheduler(supabase)
        logger.info("APScheduler started")
    except Exception as e:
        logger.error(f"APScheduler startup failed (non-fatal): {e}")

    logger.info("=== PREACT Backend ready ===")

    yield  # ── App running ──────────────────────────────────────────────────

    # Shutdown
    logger.info("=== PREACT Backend shutting down ===")
    if _scheduler and _scheduler.running:
        _scheduler.shutdown(wait=False)
        logger.info("APScheduler stopped")


# ── FastAPI app ───────────────────────────────────────────────────────────────
app = FastAPI(
    title="PREACT Traffic Intelligence API",
    description=(
        "AI-powered Bengaluru Traffic Police operational intelligence backend. "
        "Provides event forecasting, officer deployment optimisation, "
        "complaint processing, voice chat, and post-event analytics."
    ),
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# ── CORS — allow all origins (hackathon mode) ─────────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Include all 12 routers ───────────────────────────────────────────────────
from routers.health import router as health_router
from routers.events import router as events_router
from routers.forecast import router as forecast_router
from routers.deployment import router as deployment_router
from routers.counterfactual import router as counterfactual_router
from routers.complaints import router as complaints_router
from routers.chat import router as chat_router
from routers.alerts import router as alerts_router
from routers.simulate import router as simulate_router
from routers.ground_truth import router as ground_truth_router
from routers.volunteer import router as volunteer_router
from routers.memory import router as memory_router

app.include_router(health_router)
app.include_router(events_router)
app.include_router(forecast_router)
app.include_router(deployment_router)
app.include_router(counterfactual_router)
app.include_router(complaints_router)
app.include_router(chat_router)
app.include_router(alerts_router)
app.include_router(simulate_router)
app.include_router(ground_truth_router)
app.include_router(volunteer_router)
app.include_router(memory_router)

from fastapi.responses import RedirectResponse

@app.get("/")
async def root_redirect():
    """Redirect root path to interactive Swagger API docs."""
    return RedirectResponse(url="/docs")

logger.info("All 12 routers registered")

