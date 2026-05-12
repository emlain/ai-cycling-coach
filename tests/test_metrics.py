"""Tests for shared.metrics."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from shared import metrics, workout_classifier  # noqa: E402


def test_np_steady_300w_equals_300():
    """NP di 1h costanti a 300W deve essere ~300W."""
    watts = [300.0] * 3600
    np = metrics.compute_np(watts)
    assert np is not None
    assert abs(np - 300.0) < 1.0


def test_np_intervals_higher_than_avg():
    """NP di intervalli alternati 100/500W deve essere > 300 (avg)."""
    watts = ([500.0] * 60 + [100.0] * 60) * 30  # 30 min totali alternati
    avg = sum(watts) / len(watts)  # = 300
    np = metrics.compute_np(watts)
    assert np is not None
    assert np > avg  # NP penalizza variabilità


def test_np_too_short_returns_none():
    assert metrics.compute_np([200.0] * 20) is None
    assert metrics.compute_np([]) is None
    assert metrics.compute_np(None) is None


def test_if_and_tss():
    np = 250.0
    ftp = 250.0
    if_val = metrics.compute_if(np, ftp)
    assert if_val == 1.0
    tss = metrics.compute_tss(3600, np, ftp)
    assert tss is not None
    assert abs(tss - 100.0) < 0.5  # 1h a soglia = 100 TSS


def test_vi():
    assert metrics.compute_vi(250, 250) == 1.0
    assert metrics.compute_vi(275, 250) == 1.1


def test_best_efforts():
    # 1h a 300W → best 5s, 1min, 5min, 20min, 1h = 300W
    watts = [300.0] * 3600
    bests = metrics.compute_best_efforts(watts)
    assert bests[5] == 300.0
    assert bests[60] == 300.0
    assert bests[1200] == 300.0
    assert bests[3600] == 300.0


def test_best_efforts_with_spike():
    watts = [200.0] * 3600
    # Inserisce sprint di 5s a 1000W
    for i in range(100, 105):
        watts[i] = 1000.0
    bests = metrics.compute_best_efforts(watts)
    assert bests[5] == 1000.0
    assert bests[60] < 300  # 1 min: lo sprint diluito
    assert bests[3600] < 250  # 1h: media bassa


def test_decoupling_positive_when_hr_drifts():
    n = 3600
    watts = [200.0] * n
    hr = [140.0] * (n // 2) + [160.0] * (n // 2)  # HR sale nella 2a metà
    decoupling = metrics.compute_decoupling_pct(watts, hr)
    assert decoupling is not None
    assert decoupling > 0  # drift positivo


def test_decoupling_near_zero_when_steady():
    n = 3600
    watts = [200.0] * n
    hr = [145.0] * n
    decoupling = metrics.compute_decoupling_pct(watts, hr)
    assert decoupling is not None
    assert abs(decoupling) < 0.5


def test_decoupling_too_short_returns_none():
    assert metrics.compute_decoupling_pct([200] * 100, [140] * 100) is None


def test_classification_vo2():
    tiz = {"recovery": 600, "endurance": 600, "tempo": 600, "sweetspot": 0,
           "threshold": 0, "vo2": 600, "anaerobic": 0, "sprint": 0}
    result = workout_classifier.classify(
        time_in_zone_sec=tiz,
        intervals=[{"zone": "vo2"}] * 3,
        total_time_sec=2400,
        strava_type="VirtualRide",
    )
    assert result["type"] == "vo2max_intervals"
    assert result["primary_system"] == "vo2"
    assert result["structured"] is True


def test_classification_endurance():
    tiz = {"recovery": 1200, "endurance": 4800, "tempo": 0, "sweetspot": 0,
           "threshold": 0, "vo2": 0, "anaerobic": 0, "sprint": 0}
    result = workout_classifier.classify(
        time_in_zone_sec=tiz, intervals=[], total_time_sec=6000, strava_type="Ride",
    )
    assert result["type"] == "endurance"


def test_classification_real_sample():
    """Test sul sample workout v2 reale."""
    sample_path = ROOT / "tests" / "sample_workout_v2.json"
    data = json.loads(sample_path.read_text())
    tiz = data["laps_summary"]["time_in_zone_sec"]
    total = data["laps_summary"]["total_laps_time_sec"]
    result = workout_classifier.classify(
        time_in_zone_sec=tiz,
        intervals=data["intervals_detected"],
        total_time_sec=total,
        strava_type=data["raw"]["strava"]["type"],
    )
    # Il sample ha 60s di VO2 → dovrebbe essere classificato vo2max o threshold
    assert result["type"] in ("vo2max_intervals", "threshold", "mixed")
