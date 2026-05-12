"""AI Cycling Coach — Function App (schema v3).

Trigger: Event Grid BlobCreated su container `aggregator/`.
Output: container `metrics/`, prefisso `daily/`, schema `daily-v3-coachready`.

Sprint 1.1: aggiunto stream loading da `streams/{activity_id}.json`
e calcolo metriche di potenza (NP, IF, TSS, VI, decoupling, best efforts).
"""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime
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
    ("recovery", 0.00, 0.55),
    ("endurance", 0.55, 0.75),
    ("tempo", 0.75, 0.88),
    ("sweetspot", 0.88, 0.94),
    ("threshold", 0.94, 1.06),
    ("vo2", 1.06, 1.20),
    ("anaerobic", 1.20, 1.40),
    ("sprint", 1.40, 99.0),
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
    return datetime.now(UTC).isoformat()


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
            "laps_count": 0,
            "total_laps_time_sec": 0,
            "watts": None,
            "hr": None,
            "cadence": None,
            "time_in_zone_sec": None,
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
        candidates.append(
            {
                "lap_index": _safe_int(lap.get("lap_index")),
                "name": lap.get("name"),
                "dur_sec": t,
                "avg_watts": w,
                "avg_hr": _safe_float(lap.get("average_heartrate")),
                "avg_cadence": _safe_float(lap.get("average_cadence")),
                "rel_ftp": rel,
                "zone": zone,
            }
        )
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
        day = datetime.now(UTC).strftime("%Y-%m-%d")

    # 2) Try to load stream
    stream = stream_loader.try_load_stream(bsc, STREAMS_CONTAINER, activity_id)
    has_stream = stream is not None
    logging.info("Stream loaded: %s (activity_id=%s)", has_stream, activity_id)

    # 3) RAW pass-through
    raw_strava = {
        "id": strava.get("id"),
        "date": strava.get("date"),
        "name": strava.get("name"),
        "type": strava.get("type"),
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
    work_kj_proxy = (
        ((avg_power or 0) * moving_time_sec / 1000.0)
        if (moving_time_sec > 0 and avg_power)
        else None
    )
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
            "ctl": ctl,
            "atl": atl,
            "tsb": tsb,
            "atl_ctl_ratio": atl_ctl_ratio,
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
