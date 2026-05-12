"""Cycling metrics computations.

All functions are stubs in Sprint 0. They will be implemented in Sprint 1 once
we add the Strava streams (watts/hr per second) to the ingest pipeline.

References:
  - Normalized Power (NP): Coggan, "Training and Racing with a Power Meter"
  - Decoupling (Pa:Hr): Friel, "The Cyclist's Training Bible"
"""
from __future__ import annotations

from collections.abc import Sequence


def compute_np(watts_stream: Sequence[float]) -> float:
    """Normalized Power: 4th-root of mean of (30s rolling avg)^4.

    Args:
        watts_stream: 1-Hz power samples in watts.

    Returns:
        Normalized Power in watts.
    """
    raise NotImplementedError("Implement in Sprint 1")


def compute_if(np_watts: float, ftp_watts: float) -> float:
    """Intensity Factor = NP / FTP."""
    raise NotImplementedError("Implement in Sprint 1")


def compute_tss(duration_sec: int, np_watts: float, ftp_watts: float) -> float:
    """Training Stress Score = (sec * NP * IF) / (FTP * 3600) * 100."""
    raise NotImplementedError("Implement in Sprint 1")


def compute_variability_index(np_watts: float, avg_watts: float) -> float:
    """VI = NP / avg power. Closer to 1.0 = steadier effort."""
    raise NotImplementedError("Implement in Sprint 1")


def compute_decoupling_pct(
    watts_stream: Sequence[float],
    hr_stream: Sequence[float],
) -> float:
    """Aerobic decoupling (Pa:Hr) between first and second half of the ride.

    Returns:
        Decoupling percentage. < 5% = solid aerobic base.
    """
    raise NotImplementedError("Implement in Sprint 1")


def compute_best_efforts(
    watts_stream: Sequence[float],
    windows_sec: Sequence[int] = (5, 15, 60, 300, 600, 1200, 3600),
) -> dict[int, float]:
    """Max average power for each rolling window."""
    raise NotImplementedError("Implement in Sprint 1")
