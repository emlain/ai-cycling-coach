#!/usr/bin/env bash
# AI Cycling Coach — Sprint 1.1: metriche v3 da Strava streams
set -euo pipefail

echo "🚴 Sprint 1.1: extending Function App to schema v3..."

# Branch nuovo da main aggiornato
git checkout main
git pull
git checkout -b feat/sprint-1-metrics-v3 2>/dev/null || git checkout feat/sprint-1-metrics-v3

# Pulizia: rimuoviamo le folder v1-style del Sprint 0 (non usate)
rm -rf backend/ingest_function backend/api_function

# Backend root: nuova Function v3
mkdir -p backend/shared

cat > backend/function_app.py <<'PYEOF'
"""AI Cycling Coach — Function App (schema v3).

Trigger: Event Grid BlobCreated su container `aggregator/`.
Output: container `metrics/`, prefisso `daily/`, schema `daily-v3-coachready`.

Sprint 1.1: aggiunto stream loading da `streams/{activity_id}.json`
e calcolo metriche di potenza (NP, IF, TSS, VI, decoupling, best efforts).
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any
from urllib.parse import unquote, urlparse

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from shared import metrics, stream_loader, workout_classifier

# =========================
# CONFIG
# =========================
app = func.FunctionApp()

SCHEMA_VERSION = "daily-v3-coachready"

STORAGE_ACCOUNT = "emlainaicoachsa"
IN_CONTAINER = "aggregator"
STREAMS_CONTAINER = "streams"
OUT_CONTAINER = "metrics"
OUT_PREFIX = "daily"

MAX_INTERVALS_DETECTED = 12
MIN_LAP_SEC_FOR_INTERVAL = 30
MIN_RELFTP_FOR_INTERVAL = 0.75
TEMPO_MIN_LAP_SEC = 360

ZONES = [
    ("recovery",   0.00, 0.55),
    ("endurance",  0.55, 0.75),
    ("tempo",      0.75, 0.88),
    ("sweetspot",  0.88, 0.94),
    ("threshold",  0.94, 1.06),
    ("vo2",        1.06, 1.20),
    ("anaerobic",  1.20, 1.40),
    ("sprint",     1.40, 99.0),
]


# =========================
# HELPERS (laps logic — invariata da v2)
# =========================
def _safe_float(x: Any) -> float | None:
    try:
        return None if x is None else float(x)
    except Exception:
        return None


def _safe_int(x: Any) -> int | None:
    try:
        return None if x is None else int(x)
    except Exception:
        return None


def _now_utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _zone_from_relftp(relftp: float | None) -> str:
    if relftp is None:
        return "unknown"
    for name, lo, hi in ZONES:
        if lo <= relftp < hi:
            return name
    return "unknown"


def _calc_zone_times_from_laps(laps: list[dict], eftp: float | None) -> tuple[int, int]:
    if not laps or not eftp or eftp <= 0:
        return 0, 0
    ss_time = vo2_time = 0
    for lap in laps:
        w = _safe_float(lap.get("average_watts"))
        t = _safe_int(lap.get("elapsed_time")) or 0
        if not w or t <= 0:
            continue
        rel = w / eftp
        if 0.88 <= rel <= 0.94:
            ss_time += t
        if 1.06 <= rel <= 1.20:
            vo2_time += t
    return ss_time, vo2_time


def _summarize_laps(laps: list[dict], eftp: float | None) -> dict:
    if not laps:
        return {
            "laps_count": 0, "total_laps_time_sec": 0,
            "watts": None, "hr": None, "cadence": None, "time_in_zone_sec": None,
        }
    watts_vals: list[float] = []
    hr_vals: list[float] = []
    cad_vals: list[float] = []
    total_time = 0
    time_in_zone = {z[0]: 0 for z in ZONES} if (eftp and eftp > 0) else None

    for lap in laps:
        t = _safe_int(lap.get("elapsed_time")) or 0
        total_time += max(t, 0)
        w = _safe_float(lap.get("average_watts"))
        if w is not None:
            watts_vals.append(w)
        hr = _safe_float(lap.get("average_heartrate"))
        if hr is not None:
            hr_vals.append(hr)
        cad = _safe_float(lap.get("average_cadence"))
        if cad is not None:
            cad_vals.append(cad)
        if time_in_zone is not None and w is not None and t > 0:
            rel = w / eftp
            z = _zone_from_relftp(rel)
            time_in_zone[z] = time_in_zone.get(z, 0) + t

    def _stats(arr: list[float]) -> dict | None:
        if not arr:
            return None
        return {"avg": sum(arr) / len(arr), "min": min(arr), "max": max(arr)}

    return {
        "laps_count": len(laps),
        "total_laps_time_sec": total_time,
        "watts": _stats(watts_vals),
        "hr": _stats(hr_vals),
        "cadence": _stats(cad_vals),
        "time_in_zone_sec": time_in_zone,
    }


def _detect_intervals_from_laps(laps: list[dict], eftp: float | None) -> list[dict]:
    if not laps or not eftp or eftp <= 0:
        return []
    candidates = []
    for lap in laps:
        t = _safe_int(lap.get("elapsed_time")) or 0
        if t <= 0:
            continue
        w = _safe_float(lap.get("average_watts"))
        if w is None or w <= 0:
            continue
        rel = w / eftp
        if rel < MIN_RELFTP_FOR_INTERVAL:
            continue
        zone = _zone_from_relftp(rel)
        if zone == "tempo" and t < TEMPO_MIN_LAP_SEC:
            continue
        if zone != "tempo" and t < MIN_LAP_SEC_FOR_INTERVAL:
            continue
        candidates.append({
            "lap_index": _safe_int(lap.get("lap_index")),
            "name": lap.get("name"),
            "dur_sec": t,
            "avg_watts": w,
            "avg_hr": _safe_float(lap.get("average_heartrate")),
            "avg_cadence": _safe_float(lap.get("average_cadence")),
            "rel_ftp": rel,
            "zone": zone,
        })
    candidates.sort(key=lambda x: (x["rel_ftp"], x["avg_watts"]), reverse=True)
    return candidates[:MAX_INTERVALS_DETECTED]


def _extract_blob_name(subject: str, data: dict, container_name: str) -> str:
    subject = subject or ""
    marker = f"/containers/{container_name}/blobs/"
    if marker in subject:
        return subject.split(marker, 1)[1]
    if isinstance(data, dict):
        url = data.get("url") or data.get("blobUrl")
        if url:
            p = urlparse(url)
            parts = p.path.split("/", 2)
            if len(parts) >= 3 and parts[1].lower() == container_name.lower():
                return unquote(parts[2])
    raise ValueError(f"Cannot extract blob name: subject={subject!r}")


def _get_blob_service_client() -> BlobServiceClient:
    return BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net",
        credential=DefaultAzureCredential(),
    )


# =========================
# EVENT GRID TRIGGER
# =========================
@app.function_name(name="ComputeMetricsFromEventGrid")
@app.event_grid_trigger(arg_name="event")
def compute_metrics_from_eventgrid(event: func.EventGridEvent) -> None:
    data = event.get_json()
    subject = getattr(event, "subject", None)

    logging.info("EventGrid received: subject=%r", subject)

    blob_name = _extract_blob_name(subject, data, IN_CONTAINER)
    logging.info("Aggregator blob: %s", blob_name)

    bsc = _get_blob_service_client()

    # 1) Read aggregator blob
    in_blob = bsc.get_blob_client(container=IN_CONTAINER, blob=blob_name)
    payload = json.loads(in_blob.download_blob().readall().decode("utf-8"))

    activity_id = str(payload.get("activity_id") or payload.get("strava_data", {}).get("id") or "")
    strava = payload.get("strava_data", {}) or {}
    intervals_data = payload.get("intervals_data", {}) or {}
    laps = payload.get("laps_data", []) or []

    day = intervals_data.get("date")
    if not day and strava.get("date"):
        day = strava["date"][:10]
    if not day:
        day = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # 2) Try to load stream
    stream = stream_loader.try_load_stream(bsc, STREAMS_CONTAINER, activity_id)
    has_stream = stream is not None
    logging.info("Stream loaded: %s (activity_id=%s)", has_stream, activity_id)

    # 3) RAW pass-through
    raw_strava = {
        "id": strava.get("id"), "date": strava.get("date"),
        "name": strava.get("name"), "type": strava.get("type"),
        "distance_km": _safe_float(strava.get("distance_km")),
        "moving_time_min": _safe_int(strava.get("moving_time_min")),
        "elevation": _safe_float(strava.get("elevation")),
        "avg_power": _safe_float(strava.get("avg_power")),
        "avg_hr": _safe_float(strava.get("avg_hr")),
        "suffer_score": _safe_float(strava.get("suffer_score")),
    }
    hrv_raw = _safe_float(intervals_data.get("hrv"))
    rhr_raw = _safe_float(intervals_data.get("resting_hr"))
    sleep_hours_raw = _safe_float(intervals_data.get("sleep_hours"))
    raw_intervals = {
        "date": intervals_data.get("date"),
        "fitness": _safe_float(intervals_data.get("fitness")),
        "fatigue": _safe_float(intervals_data.get("fatigue")),
        "eftp": _safe_float(intervals_data.get("eftp")),
        "pMax": _safe_float(intervals_data.get("pMax")),
        "hrv_raw": hrv_raw,
        "resting_hr_raw": rhr_raw,
        "sleep_hours_raw": sleep_hours_raw,
        "sleep_score": _safe_float(intervals_data.get("sleep_score")),
        "steps": _safe_int(intervals_data.get("steps")),
        "readiness": _safe_float(intervals_data.get("readiness")),
    }

    # 4) Load / efficiency
    ctl = raw_intervals["fitness"]
    atl = raw_intervals["fatigue"]
    tsb = (ctl - atl) if (ctl is not None and atl is not None) else None
    atl_ctl_ratio = (atl / ctl) if (ctl and atl is not None and ctl != 0) else None

    eftp = raw_intervals["eftp"]
    avg_power = raw_strava["avg_power"]
    avg_hr = raw_strava["avg_hr"]

    moving_time_min = raw_strava["moving_time_min"] or 0
    moving_time_sec = moving_time_min * 60

    intensity_proxy = (avg_power / eftp) if (avg_power is not None and eftp and eftp > 0) else None
    work_kj_proxy = ((avg_power or 0) * moving_time_sec / 1000.0) if (moving_time_sec > 0 and avg_power) else None
    ef_daily = (avg_power / avg_hr) if (avg_power is not None and avg_hr and avg_hr != 0) else None

    # 5) Laps-based features (invariate)
    ss_time_sec, vo2_time_sec = _calc_zone_times_from_laps(laps, eftp)
    laps_summary = _summarize_laps(laps, eftp)
    intervals_detected = _detect_intervals_from_laps(laps, eftp)

    coach_features = {
        "intensity_proxy": intensity_proxy,
        "work_kj_proxy": work_kj_proxy,
        "ss_time_sec": ss_time_sec,
        "vo2_time_sec": vo2_time_sec,
        "training_load": {
            "ctl": ctl, "atl": atl, "tsb": tsb, "atl_ctl_ratio": atl_ctl_ratio,
        },
        "efficiency": {"ef_daily": ef_daily},
    }

    # 6) STREAM-BASED METRICS (NEW v3)
    power_metrics = None
    hr_metrics = None
    best_efforts = None

    if has_stream and stream is not None:
        watts_arr = stream.get("watts")
        hr_arr = stream.get("heartrate")
        time_arr = stream.get("time")

        if watts_arr:
            np_val = metrics.compute_np(watts_arr)
            if_val = metrics.compute_if(np_val, eftp) if (np_val and eftp) else None
            duration_sec = time_arr[-1] if (time_arr and len(time_arr) > 0) else len(watts_arr)
            tss_val = metrics.compute_tss(duration_sec, np_val, eftp) if (np_val and eftp) else None
            avg_w_stream = sum(w for w in watts_arr if w) / len(watts_arr) if watts_arr else None
            vi_val = metrics.compute_vi(np_val, avg_w_stream) if (np_val and avg_w_stream) else None
            work_kj = metrics.compute_work_kj(watts_arr, time_arr)

            power_metrics = {
                "avg": avg_w_stream,
                "np": np_val,
                "if": if_val,
                "tss": tss_val,
                "vi": vi_val,
                "work_kj": work_kj,
                "duration_sec": duration_sec,
            }
            best_efforts = metrics.compute_best_efforts(watts_arr)

        if watts_arr and hr_arr:
            decoupling = metrics.compute_decoupling_pct(watts_arr, hr_arr)
            hr_drift = metrics.compute_hr_drift_pct(hr_arr)
            hr_metrics = {
                "avg": sum(h for h in hr_arr if h) / len(hr_arr) if hr_arr else None,
                "max": max((h for h in hr_arr if h), default=None),
                "decoupling_pct": decoupling,
                "drift_pct": hr_drift,
            }

    # 7) Workout classification
    classification = workout_classifier.classify(
        time_in_zone_sec=laps_summary.get("time_in_zone_sec"),
        intervals=intervals_detected,
        total_time_sec=laps_summary.get("total_laps_time_sec", 0) or moving_time_sec,
        strava_type=raw_strava.get("type"),
    )

    # 8) Data quality flags
    data_quality = {
        "has_power": avg_power is not None,
        "has_hr": avg_hr is not None,
        "has_stream": has_stream,
        "has_wellness": hrv_raw not in (None, 0, 0.0) and rhr_raw not in (None, 0, 0.0),
        "indoor": raw_strava.get("type") in ("VirtualRide", "Workout"),
    }

    # 9) Athlete context snapshot
    athlete_context = {
        "ftp_used": eftp,
        # weight_kg / age verranno aggiunti in Sprint 2 quando avremo il profilo
    }

    # 10) Compose v3 output
    out = {
        "schema_version": SCHEMA_VERSION,
        "generated_utc": _now_utc_iso(),
        "date": day,
        "activity_id": activity_id,
        "source_blob": f"{IN_CONTAINER}/{blob_name}",
        "athlete_context": athlete_context,
        "data_quality": data_quality,
        "raw": {"strava": raw_strava, "intervals": raw_intervals},
        "coach_features": coach_features,
        "power_metrics": power_metrics,
        "hr_metrics": hr_metrics,
        "best_efforts": best_efforts,
        "workout_classification": classification,
        "laps_summary": laps_summary,
        "intervals_detected": intervals_detected,
    }

    out_name = f"{OUT_PREFIX}/{day}_master_{activity_id}.metrics.json"
    out_blob = bsc.get_blob_client(container=OUT_CONTAINER, blob=out_name)
    out_blob.upload_blob(json.dumps(out, ensure_ascii=False), overwrite=True)

    logging.info("Wrote v3 metrics: %s/%s (has_stream=%s)", OUT_CONTAINER, out_name, has_stream)
PYEOF

cat > backend/shared/metrics.py <<'PYEOF'
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
PYEOF

cat > backend/shared/stream_loader.py <<'PYEOF'
"""Graceful loading of Strava streams from blob storage."""
from __future__ import annotations

import json
import logging
from typing import Any

from azure.core.exceptions import ResourceNotFoundError
from azure.storage.blob import BlobServiceClient


def try_load_stream(
    bsc: BlobServiceClient,
    container: str,
    activity_id: str,
) -> dict[str, list[Any]] | None:
    """Load stream JSON for {activity_id}.

    Returns:
        Dict with keys watts/heartrate/time/cadence/distance/altitude
        (each a list of values), or None if the stream blob does not exist.
    """
    if not activity_id:
        return None
    blob_name = f"{activity_id}.json"
    try:
        bc = bsc.get_blob_client(container=container, blob=blob_name)
        raw = bc.download_blob().readall().decode("utf-8-sig")  # gestisce BOM
        parsed = json.loads(raw)
    except ResourceNotFoundError:
        logging.info("Stream not found: %s/%s (degrading to v2 baseline)", container, blob_name)
        return None
    except Exception as e:
        logging.warning("Stream load failed for %s/%s: %s", container, blob_name, e)
        return None

    # Strava restituisce {watts: {data: [...]}, hr: {data: [...]}, ...}
    out: dict[str, list[Any]] = {}
    if isinstance(parsed, dict):
        for key in ("watts", "heartrate", "time", "cadence", "distance", "altitude", "velocity_smooth"):
            section = parsed.get(key)
            if isinstance(section, dict) and isinstance(section.get("data"), list):
                out[key] = section["data"]
    return out or None
PYEOF

cat > backend/shared/workout_classifier.py <<'PYEOF'
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
PYEOF

# Update models.py with v3 additions
cat > backend/shared/models.py <<'PYEOF'
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
PYEOF

# Tests
cat > tests/test_metrics.py <<'PYEOF'
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
PYEOF

# Update backend README
cat > backend/README.md <<'EOF'
# Backend — Azure Function (Python 3.11)

## Architettura

```
EventGrid (BlobCreated su /aggregator)
        │
        ▼
function_app.py: ComputeMetricsFromEventGrid
        │
        ├─ legge /aggregator/{blob}.json
        ├─ legge /streams/{activity_id}.json (se esiste)
        ├─ shared/metrics.py        → NP, IF, TSS, VI, decoupling, best efforts
        ├─ shared/workout_classifier.py → classificazione tipo workout
        └─ scrive /metrics/daily/{date}_master_{id}.metrics.json (schema v3)
```

## Local run

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp local.settings.json.example local.settings.json
# Edita local.settings.json con le tue credenziali (NON committare)
func start
```

## Test

```bash
pip install pytest ruff
pytest -v
```

## Deploy

```bash
# Da root del repo
cd backend
func azure functionapp publish emlainaicoach --python
```

> ⚠️ Prima del primo deploy v3, **fai backup del codice esistente** (è già in `/azure-current-state/function-app-existing/`).
EOF

echo "✅ Sprint 1.1 scaffold complete!"
echo ""
echo "Next steps:"
echo "  git add ."
echo "  git status   # verifica i file"
echo "  git commit -m 'feat(backend): schema v3 with stream-based metrics (NP, IF, TSS, decoupling)'"
echo "  git push -u origin feat/sprint-1-metrics-v3"
echo ""
echo "Then open PR:"
echo "  https://github.com/emlain/ai-cycling-coach/compare/main...feat/sprint-1-metrics-v3"