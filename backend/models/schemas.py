from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime


class DeployRequest(BaseModel):
    event_id: str
    available_officer_ids: List[str]


class JunctionScenario(BaseModel):
    junction: str
    officer_count: int
    start_time: str
    barricade_active: bool


class SimulateRequest(BaseModel):
    event_id: str
    scenario: List[JunctionScenario]


class JunctionStress(BaseModel):
    junction: str
    stress_level: int  # 1-5


class GroundTruthRequest(BaseModel):
    event_id: str
    officer_id: str
    actual_crowd_size: int
    junction_stress: List[JunctionStress]
    bottlenecks: List[str]
    notes: Optional[str] = None


class VolunteerSignupRequest(BaseModel):
    citizen_id: str
    date: str
    start_time: str
    end_time: str
    junction: str


class VolunteerUpdateRequest(BaseModel):
    status: str  # 'approved' | 'rejected'
    reviewed_by: str


class CounterfactualRequest(BaseModel):
    event_id: str


class ComplaintResponse(BaseModel):
    valid: bool
    reason: Optional[str]
    complaint_id: str
    confidence_score: float


class ForecastRow(BaseModel):
    zone: str
    corridor: str
    forecast_hour: datetime
    severity: float
    confidence_lower: float
    confidence_upper: float


class ForecastRequest(BaseModel):
    event_id: str


class ChatResponse(BaseModel):
    answer_text: str
    transcript: str


class SimulationZone(BaseModel):
    zone: str
    junction: str
    severity_curve: List[float]
    peak_hour: int
    risk_tier: str


class SimulationSummary(BaseModel):
    total_congestion_min: float
    vs_optimal_delta: float
    recommendation: str


class SimulationResult(BaseModel):
    zones: List[SimulationZone]
    summary: SimulationSummary


class CounterfactualResult(BaseModel):
    actual_congestion: float
    preact_estimate: float
    avoided_minutes: float
    regret_score: float


class GroundTruthResponse(BaseModel):
    success: bool
    prediction_error: dict


class DeploymentPlanItem(BaseModel):
    officer_id: str
    officer_name: str
    badge_number: str
    junction: str
    lat: float
    lng: float
    start_time: str
    end_time: str
    priority: str


class ErrorResponse(BaseModel):
    error: str
    detail: Optional[str] = None
