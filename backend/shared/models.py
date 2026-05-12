"""Pydantic models for the daily-v2-coachready schema.

Faithfully represents the JSON produced by the existing ingest Function.
Used both by the ingest_function (validation) and the api_function (serialization).
"""
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
    ctl: float
    atl: float
    tsb: float
    atl_ctl_ratio: float | None = None


class Efficiency(BaseModel):
    ef_daily: float | None = None


class CoachFeatures(BaseModel):
    intensity_proxy: float | None = None
    work_kj_proxy: float | None = None
    ss_time_sec: int = 0
    vo2_time_sec: int = 0
    training_load: TrainingLoad
    efficiency: Efficiency = Field(default_factory=Efficiency)


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
    time_in_zone_sec: TimeInZoneSec = Field(default_factory=TimeInZoneSec)


class DetectedInterval(BaseModel):
    lap_index: int
    name: str
    dur_sec: int
    avg_watts: float
    avg_hr: float | None = None
    avg_cadence: float | None = None
    rel_ftp: float
    zone: Zone


class WorkoutV2(BaseModel):
    """Top-level model for schema_version = daily-v2-coachready."""
    model_config = ConfigDict(extra="allow")

    schema_version: str
    generated_utc: datetime
    date: date
    activity_id: str
    source_blob: str | None = None
    raw: RawSection
    coach_features: CoachFeatures
    laps_summary: LapsSummary
    intervals_detected: list[DetectedInterval] = Field(default_factory=list)
