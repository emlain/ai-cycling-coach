"""Heuristic workout type classification based on time-in-zone and intervals."""
from __future__ import annotations

from typing import Literal

WorkoutType = Literal[
    "recovery", "endurance", "tempo", "sweetspot",
    "threshold", "vo2max_intervals", "anaerobic", "race", "mixed", "unknown",
]


def classify(
    time_in_zone_sec: dict | None,
    intervals: list[dict] | None,
    total_time_sec: int,
    strava_type: str | None,
) -> dict:
    """Classifica il tipo di allenamento usando euristica basata su time-in-zone.

    Returns:
        {
            "type": WorkoutType,
            "primary_system": "aerobic" | "tempo" | "threshold" | "vo2" | ...,
            "structured": bool,
            "confidence": 0..1,
        }
    """
    if not time_in_zone_sec or total_time_sec <= 0:
        return {
            "type": "unknown", "primary_system": "unknown",
            "structured": False, "confidence": 0.0,
        }

    pct = {k: (v / total_time_sec) for k, v in time_in_zone_sec.items()}

    if pct.get("vo2", 0) > 0.05:
        wtype: WorkoutType = "vo2max_intervals"
        primary = "vo2"
    elif pct.get("threshold", 0) > 0.15:
        wtype, primary = "threshold", "threshold"
    elif pct.get("sweetspot", 0) > 0.20:
        wtype, primary = "sweetspot", "sweetspot"
    elif pct.get("anaerobic", 0) + pct.get("sprint", 0) > 0.05:
        wtype, primary = "anaerobic", "anaerobic"
    elif pct.get("tempo", 0) > 0.30:
        wtype, primary = "tempo", "tempo"
    elif pct.get("recovery", 0) > 0.70:
        wtype, primary = "recovery", "aerobic"
    elif (pct.get("endurance", 0) + pct.get("recovery", 0)) > 0.75:
        wtype, primary = "endurance", "aerobic"
    else:
        wtype, primary = "mixed", "mixed"

    structured = bool(intervals and len(intervals) >= 3)

    # Confidence: quanto è "puro" il workout (più tempo in una zona = più sicuro)
    top_pct = max(pct.values()) if pct else 0
    confidence = min(1.0, top_pct + (0.2 if structured else 0))

    return {
        "type": wtype,
        "primary_system": primary,
        "structured": structured,
        "confidence": round(confidence, 2),
    }
