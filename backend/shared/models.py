"""Pydantic models for daily-v3-coachready schema."""
from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Zone = Literal[
    "recovery", "endurance", "tempo", "sweetspot",
    "threshold", "vo2", "anaerobic", "sprint",
]


class StravaRaw(BaseModel):
    model_config = ConfigDict(extra="allow")
    id: int
    date: datetime
    name: str
    type: str
    distance_km: float
    moving_time_min: float
    elevation: float
    avg_power: float | None = None
    avg_hr: float | None = None
    suffer_score: float | None = None


class IntervalsRaw(BaseModel):
    model_config = ConfigDict(extra="allow")
    date: date
    fitness: float = 0.0
    fatigue: float = 0.0
    eftp: float | None = None
    pMax: float | None = None
    hrv_raw: float = 0.0
    resting_hr_raw: float = 0.0
    sleep_hours_raw: float = 0.0
    sleep_score: float = 0.0
    steps: int = 0
    readiness: float = 0.0


class RawSection(BaseModel):
    strava: StravaRaw
    intervals: IntervalsRaw


class TrainingLoad(BaseModel):
    ctl: float | None = None
    atl: float | None = None
    tsb: float | None = None
    atl_ctl_ratio: float | None = None


class CoachFeatures(BaseModel):
    intensity_proxy: float | None = None
    work_kj_proxy: float | None = None
    ss_time_sec: int = 0
    vo2_time_sec: int = 0
    training_load: TrainingLoad
    efficiency: dict = Field(default_factory=dict)


class StatTriple(BaseModel):
    avg: float | None = None
    min: float | None = None
    max: float | None = None


class TimeInZoneSec(BaseModel):
    recovery: int = 0
    endurance: int = 0
    tempo: int = 0
    sweetspot: int = 0
    threshold: int = 0
    vo2: int = 0
    anaerobic: int = 0
    sprint: int = 0


class LapsSummary(BaseModel):
    laps_count: int
    total_laps_time_sec: int
    watts: StatTriple = Field(default_factory=StatTriple)
    hr: StatTriple = Field(default_factory=StatTriple)
    cadence: StatTriple = Field(default_factory=StatTriple)
    time_in_zone_sec: TimeInZoneSec | None = None


class DetectedInterval(BaseModel):
    lap_index: int | None = None
    name: str | None = None
    dur_sec: int
    avg_watts: float
    avg_hr: float | None = None
    avg_cadence: float | None = None
    rel_ftp: float
    zone: Zone


# --- v3 NEW ---
class DataQuality(BaseModel):
    has_power: bool
    has_hr: bool
    has_stream: bool
    has_wellness: bool
    indoor: bool


class AthleteContext(BaseModel):
    ftp_used: float | None = None
    weight_kg: float | None = None
    age: int | None = None


class PowerMetrics(BaseModel):
    avg: float | None = None
    np: float | None = None
    if_: float | None = Field(default=None, alias="if")
    tss: float | None = None
    vi: float | None = None
    work_kj: float | None = None
    duration_sec: float | None = None

    model_config = ConfigDict(populate_by_name=True)


class HrMetrics(BaseModel):
    avg: float | None = None
    max: float | None = None
    decoupling_pct: float | None = None
    drift_pct: float | None = None


class WorkoutClassification(BaseModel):
    type: str
    primary_system: str
    structured: bool
    confidence: float


class WorkoutV3(BaseModel):
    """Top-level model for schema_version = daily-v3-coachready."""
    model_config = ConfigDict(extra="allow")

    schema_version: str
    generated_utc: datetime
    date: date
    activity_id: str
    source_blob: str | None = None
    athlete_context: AthleteContext = Field(default_factory=AthleteContext)
    data_quality: DataQuality
    raw: RawSection
    coach_features: CoachFeatures
    power_metrics: PowerMetrics | None = None
    hr_metrics: HrMetrics | None = None
    best_efforts: dict[str, float] | None = None
    workout_classification: WorkoutClassification | None = None
    laps_summary: LapsSummary
    intervals_detected: list[DetectedInterval] = Field(default_factory=list)


# Backward compat alias
WorkoutV2 = WorkoutV3
