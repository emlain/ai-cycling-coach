"""Cycling power & HR metrics computations.

All functions are pure Python (no numpy) to keep the Function App lean.
Algorithms follow standard references:
  - Normalized Power (NP): Coggan, "Training and Racing with a Power Meter"
  - Decoupling (Pa:Hr): Friel, "The Cyclist's Training Bible"
  - TSS: Coggan formula
"""
from __future__ import annotations

from collections.abc import Sequence


def _clean(x: Sequence[float | int | None] | None) -> list[float]:
    if not x:
        return []
    return [float(v) if v is not None else 0.0 for v in x]


def compute_np(watts: Sequence[float | None] | None, window_sec: int = 30) -> float | None:
    """Normalized Power per algoritmo Coggan.

    1) Sostituisce None → 0
    2) Rolling avg di {window_sec} secondi
    3) Eleva alla 4ª potenza, media, radice 4ª
    """
    cleaned = _clean(watts)
    if len(cleaned) < window_sec:
        return None
    rolling: list[float] = []
    window_sum = sum(cleaned[:window_sec])
    rolling.append(window_sum / window_sec)
    for i in range(window_sec, len(cleaned)):
        window_sum += cleaned[i] - cleaned[i - window_sec]
        rolling.append(window_sum / window_sec)
    fourth_powers = [r ** 4 for r in rolling if r > 0]
    if not fourth_powers:
        return None
    return (sum(fourth_powers) / len(fourth_powers)) ** 0.25


def compute_if(np_watts: float | None, ftp_watts: float | None) -> float | None:
    """Intensity Factor = NP / FTP."""
    if not np_watts or not ftp_watts or ftp_watts <= 0:
        return None
    return np_watts / ftp_watts


def compute_tss(duration_sec: float | int, np_watts: float | None, ftp_watts: float | None) -> float | None:
    """TSS = (sec * NP * IF) / (FTP * 3600) * 100."""
    if not duration_sec or not np_watts or not ftp_watts or ftp_watts <= 0:
        return None
    if_val = np_watts / ftp_watts
    return (duration_sec * np_watts * if_val) / (ftp_watts * 3600) * 100


def compute_vi(np_watts: float | None, avg_watts: float | None) -> float | None:
    """Variability Index = NP / avg_power. ~1.0 = steady, >1.1 = molto variabile."""
    if not np_watts or not avg_watts or avg_watts <= 0:
        return None
    return np_watts / avg_watts


def compute_work_kj(watts: Sequence[float | None] | None, time_sec: Sequence[float | None] | None = None) -> float | None:
    """Total work in kJ. Assume 1Hz sampling se time non disponibile."""
    cleaned = _clean(watts)
    if not cleaned:
        return None
    if time_sec and len(time_sec) == len(cleaned):
        total_j = 0.0
        prev_t = float(time_sec[0]) if time_sec[0] is not None else 0.0
        for i in range(1, len(cleaned)):
            t = float(time_sec[i]) if time_sec[i] is not None else prev_t + 1
            dt = max(0.0, t - prev_t)
            total_j += cleaned[i] * dt
            prev_t = t
        return total_j / 1000.0
    return sum(cleaned) / 1000.0


def compute_best_efforts(
    watts: Sequence[float | None] | None,
    windows_sec: Sequence[int] = (5, 15, 60, 300, 600, 1200, 3600),
) -> dict[int, float]:
    """Max average power per ciascuna finestra (in W).

    Implementato in O(n*len(windows)) con prefix sums.
    """
    cleaned = _clean(watts)
    n = len(cleaned)
    if n == 0:
        return {}
    prefix = [0.0]
    for w in cleaned:
        prefix.append(prefix[-1] + w)
    result: dict[int, float] = {}
    for window in windows_sec:
        if n < window:
            continue
        best = 0.0
        for i in range(window, n + 1):
            avg = (prefix[i] - prefix[i - window]) / window
            if avg > best:
                best = avg
        result[window] = best
    return result


def compute_decoupling_pct(
    watts: Sequence[float | None] | None,
    hr: Sequence[float | None] | None,
) -> float | None:
    """Aerobic decoupling (Pa:Hr) tra prima e seconda metà del workout.

    Returns valore positivo se HR sale rispetto alla potenza (drift).
    < 5%  = base aerobica solida
    > 8%  = manca endurance

    Considera solo i samples in cui sia watts>0 che hr>0.
    """
    if not watts or not hr or len(watts) != len(hr):
        return None
    n = len(watts)
    if n < 600:
        return None
    half = n // 2

    def avg_ratio(ws: Sequence, hrs: Sequence) -> float | None:
        valid_w: list[float] = []
        valid_hr: list[float] = []
        for w, h in zip(ws, hrs):
            if w is not None and h is not None and float(w) > 0 and float(h) > 0:
                valid_w.append(float(w))
                valid_hr.append(float(h))
        if not valid_w:
            return None
        return (sum(valid_w) / len(valid_w)) / (sum(valid_hr) / len(valid_hr))

    r1 = avg_ratio(watts[:half], hr[:half])
    r2 = avg_ratio(watts[half:], hr[half:])
    if r1 is None or r2 is None or r1 == 0:
        return None
    return ((r1 - r2) / r1) * 100


def compute_hr_drift_pct(hr: Sequence[float | None] | None) -> float | None:
    """HR drift tra prima e seconda metà (a parità di lavoro nominale).

    Più semplice del decoupling; utile per uscite steady-state.
    """
    if not hr:
        return None
    cleaned = [float(h) for h in hr if h and float(h) > 0]
    n = len(cleaned)
    if n < 600:
        return None
    half = n // 2
    avg1 = sum(cleaned[:half]) / half
    avg2 = sum(cleaned[half:]) / (n - half)
    if avg1 == 0:
        return None
    return ((avg2 - avg1) / avg1) * 100
