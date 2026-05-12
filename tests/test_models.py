"""Validate that the sample v2-coachready JSON parses cleanly."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from shared.models import WorkoutV2  # noqa: E402


def test_sample_workout_parses() -> None:
    sample_path = Path(__file__).parent / "sample_workout_v2.json"
    data = json.loads(sample_path.read_text())
    wk = WorkoutV2.model_validate(data)

    assert wk.schema_version == "daily-v2-coachready"
    assert wk.activity_id == "18302280862"
    assert wk.laps_summary.laps_count == 15
    assert len(wk.intervals_detected) == 2
    assert wk.intervals_detected[0].zone == "vo2"
    assert wk.coach_features.training_load.tsb < 0
