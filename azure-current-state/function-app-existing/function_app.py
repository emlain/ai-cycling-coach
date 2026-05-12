import json
import logging
from datetime import datetime, timezone
from urllib.parse import urlparse, unquote

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

# =========================
# CONFIG
# =========================
SCHEMA_VERSION = "daily-v2-coachready"

STORAGE_ACCOUNT = "emlainaicoachsa"
IN_CONTAINER = "aggregator"     # dove arrivano i JSON giornalieri (raw)
OUT_CONTAINER = "metrics"       # dove scriviamo i metrics
OUT_PREFIX = "daily"            # metrics/daily/...

# Intervals extraction
MAX_INTERVALS_DETECTED = 12     # quanti laps "significativi" mettere nell'output
MIN_LAP_SEC_FOR_INTERVAL = 30   # ignora laps troppo corti (rumore)
MIN_RELFTP_FOR_INTERVAL = 0.75  # minima intensità per considerare un lap un "intervallo"
TEMPO_MIN_LAP_SEC = 360  # 6 minuti: tempo "significativo"

# Zone boundaries relative to eFTP (proxy, basato su laps)
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
# HELPERS
# =========================
def _safe_float(x):
    try:
        if x is None:
            return None
        return float(x)
    except Exception:
        return None


def _safe_int(x):
    try:
        if x is None:
            return None
        return int(x)
    except Exception:
        return None


def _now_utc_iso():
    return datetime.now(timezone.utc).isoformat()


def _zone_from_relftp(relftp: float) -> str:
    if relftp is None:
        return "unknown"
    for name, lo, hi in ZONES:
        if lo <= relftp < hi:
            return name
    return "unknown"


def _calc_zone_times_from_laps(laps, eftp):
    """
    Stima tempo in Sweet Spot e VO2 sommando elapsed_time dei laps
    classificati con average_watts / eftp.
    """
    if not laps or not eftp or eftp <= 0:
        return 0, 0

    ss_time = 0
    vo2_time = 0

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


def _summarize_laps(laps, eftp):
    """
    Produce una sintesi compatta dei laps:
    - conteggio
    - tempo totale
    - min/max/avg watts e HR (se disponibili)
    - distribuzione tempo per zone (se eftp disponibile)
    """
    if not laps:
        return {
            "laps_count": 0,
            "total_laps_time_sec": 0,
            "watts": None,
            "hr": None,
            "cadence": None,
            "time_in_zone_sec": None
        }

    watts_vals = []
    hr_vals = []
    cad_vals = []
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

    def _stats(arr):
        if not arr:
            return None
        return {
            "avg": sum(arr) / len(arr),
            "min": min(arr),
            "max": max(arr),
        }

    return {
        "laps_count": len(laps),
        "total_laps_time_sec": total_time,
        "watts": _stats(watts_vals),
        "hr": _stats(hr_vals),
        "cadence": _stats(cad_vals),
        "time_in_zone_sec": time_in_zone
    }



def _detect_intervals_from_laps(laps, eftp):
    """
    Estrae una lista di "intervalli" apparenti dai laps.
    Include anche TEMPO, ma solo se significativo (durata >= TEMPO_MIN_LAP_SEC).

    Criteri:
    - relftp >= MIN_RELFTP_FOR_INTERVAL (0.75 per includere TEMPO)
    - durata minima:
        * TEMPO: >= TEMPO_MIN_LAP_SEC (default 360s)
        * altre zone: >= MIN_LAP_SEC_FOR_INTERVAL (default 30s)
    - ordina per rel_ftp e poi watts
    """
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

        # 👉 filtro "tempo significativo"
        if zone == "tempo":
            if t < TEMPO_MIN_LAP_SEC:
                continue
        else:
            # filtro standard per tutte le altre zone
            if t < MIN_LAP_SEC_FOR_INTERVAL:
                continue

        hr = _safe_float(lap.get("average_heartrate"))
        cad = _safe_float(lap.get("average_cadence"))

        candidates.append({
            "lap_index": _safe_int(lap.get("lap_index")),
            "name": lap.get("name"),
            "dur_sec": t,
            "avg_watts": w,
            "avg_hr": hr,
            "avg_cadence": cad,
            "rel_ftp": rel,
            "zone": zone
        })

    candidates.sort(key=lambda x: (x["rel_ftp"], x["avg_watts"]), reverse=True)
    return candidates[:MAX_INTERVALS_DETECTED]

def _extract_blob_name(subject: str, data: dict, container_name: str) -> str:
    """
    Estrae il nome del blob da:
      - subject: /blobServices/default/containers/<container>/blobs/<blobname>
      - data.url: https://<account>.blob.core.windows.net/<container>/<blobname>

    IMPORTANTE:
    In Azure Functions Python, EventGridEvent.get_json() restituisce il SOLO "data",
    mentre il subject vive su event.subject.
    """
    subject = subject or ""

    # 1) prova dal subject
    marker = f"/containers/{container_name}/blobs/"
    if marker in subject:
        return subject.split(marker, 1)[1]

    # 2) fallback: prova dal data.url
    if isinstance(data, dict):
        url = data.get("url") or data.get("blobUrl")
        if url:
            p = urlparse(url)
            parts = p.path.split("/", 2)  # ["", "<container>", "<blobname...>"]
            if len(parts) >= 3 and parts[1].lower() == container_name.lower():
                return unquote(parts[2])

    raise ValueError(
        f"Impossibile estrarre blob name da subject/url: "
        f"subject='{subject}' data_keys={list(data.keys()) if isinstance(data, dict) else str(type(data))}"
    )


def _get_blob_service_client():
    credential = DefaultAzureCredential()
    return BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT}.blob.core.windows.net",
        credential=credential
    )


# =========================
# EVENT GRID TRIGGER
# =========================
@app.function_name(name="ComputeMetricsFromEventGrid")
@app.event_grid_trigger(arg_name="event")
def compute_metrics_from_eventgrid(event: func.EventGridEvent):
    """
    Riceve Event Grid "BlobCreated" (Microsoft.Storage.BlobCreated),
    scarica il JSON dal container IN_CONTAINER e scrive un JSON coach-ready nel container OUT_CONTAINER.
    """
    data = event.get_json()                      # <-- è SOLO "data"
    subject = getattr(event, "subject", None)    # <-- subject vero dell'evento

    logging.info(
        "EventGrid received: id=%s type=%s subject='%s' data_keys=%s",
        getattr(event, "id", ""),
        getattr(event, "event_type", ""),
        subject,
        list(data.keys()) if isinstance(data, dict) else str(type(data))
    )

    blob_name = _extract_blob_name(subject, data, IN_CONTAINER)
    logging.info("Blob name estratto: %s", blob_name)

    bsc = _get_blob_service_client()

    # 1) Read raw json from aggregator/<blob_name>
    in_blob = bsc.get_blob_client(container=IN_CONTAINER, blob=blob_name)
    raw = in_blob.download_blob().readall().decode("utf-8")
    payload = json.loads(raw)

    # Struttura attesa dal tuo file master (raw) 【1-1fec48】
    activity_id = str(payload.get("activity_id") or payload.get("strava_data", {}).get("id") or "")
    strava = payload.get("strava_data", {}) or {}
    intervals = payload.get("intervals_data", {}) or {}
    laps = payload.get("laps_data", []) or []

    # date: preferisci intervals_data.date, altrimenti strava_data.date ISO
    day = intervals.get("date")
    if not day:
        sd = strava.get("date")  # es: 2026-04-29T06:08:44Z 【1-1fec48】
        if sd:
            day = sd[:10]
    if not day:
        day = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    # -------------------------
    # RAW: (pass-through utile al Coach AI)
    # -------------------------
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

    # Intervals raw (manteniamo anche i raw 0 per debug)
    hrv_raw = _safe_float(intervals.get("hrv"))
    rhr_raw = _safe_float(intervals.get("resting_hr"))
    sleep_hours_raw = _safe_float(intervals.get("sleep_hours"))

    raw_intervals = {
        "date": intervals.get("date"),
        "fitness": _safe_float(intervals.get("fitness")),
        "fatigue": _safe_float(intervals.get("fatigue")),
        "eftp": _safe_float(intervals.get("eftp")),
        "pMax": _safe_float(intervals.get("pMax")),
        "hrv_raw": hrv_raw,
        "resting_hr_raw": rhr_raw,
        "sleep_hours_raw": sleep_hours_raw,
        "sleep_score": _safe_float(intervals.get("sleep_score")),
        "steps": _safe_int(intervals.get("steps")),
        "readiness": _safe_float(intervals.get("readiness")),
    }

    # -------------------------
    # LOAD / PERFORMANCE / RECOVERY
    # -------------------------
    ctl = raw_intervals["fitness"]
    atl = raw_intervals["fatigue"]
    tsb = (ctl - atl) if (ctl is not None and atl is not None) else None
    atl_ctl_ratio = (atl / ctl) if (ctl and atl is not None and ctl != 0) else None

    eftp = raw_intervals["eftp"]
    avg_power = raw_strava["avg_power"]
    avg_hr = raw_strava["avg_hr"]

    # proxy utili al coach
    moving_time_min = raw_strava["moving_time_min"] or 0
    moving_time_sec = moving_time_min * 60

    intensity_proxy = (avg_power / eftp) if (avg_power is not None and eftp and eftp > 0) else None
    work_kj_proxy = ((avg_power or 0) * moving_time_sec / 1000.0) if moving_time_sec > 0 and avg_power else None
    ef_daily = (avg_power / avg_hr) if (avg_power is not None and avg_hr and avg_hr != 0) else None

    # recovery normalized (0 => None)
    hrv = None if hrv_raw in (0, 0.0) else hrv_raw
    rhr = None if rhr_raw in (0, 0.0) else rhr_raw
    sleep_hours = None if sleep_hours_raw in (0, 0.0) else sleep_hours_raw

    # -------------------------
    # QUALITY via laps
    # -------------------------
    ss_time_sec, vo2_time_sec = _calc_zone_times_from_laps(laps, eftp)
    laps_summary = _summarize_laps(laps, eftp)
    intervals_detected = _detect_intervals_from_laps(laps, eftp)

    # -------------------------
    # COACH FEATURES (pronte per frasi)
    # -------------------------
    coach_features = {
        "intensity_proxy": intensity_proxy,          # %FTP proxy (IF-like)
        "work_kj_proxy": work_kj_proxy,              # energia proxy
        "ss_time_sec": ss_time_sec,
        "vo2_time_sec": vo2_time_sec,
        "training_load": {
            "ctl": ctl,
            "atl": atl,
            "tsb": tsb,
            "atl_ctl_ratio": atl_ctl_ratio
        },
        "efficiency": {
            "ef_daily": ef_daily
        }
    }

    out = {
        "schema_version": SCHEMA_VERSION,
        "generated_utc": _now_utc_iso(),

        "date": day,
        "activity_id": activity_id,
        "source_blob": f"{IN_CONTAINER}/{blob_name}",

        # raw pass-through (utile al coach testuale)
        "raw": {
            "strava": raw_strava,
            "intervals": raw_intervals
        },

        # derived & coach-ready
        "coach_features": coach_features,

        # compact laps info + detected intervals
        "laps_summary": laps_summary,
        "intervals_detected": intervals_detected
    }

    # 2) Write output metrics
    out_name = f"{OUT_PREFIX}/{day}_master_{activity_id}.metrics.json"
    out_blob = bsc.get_blob_client(container=OUT_CONTAINER, blob=out_name)
    out_blob.upload_blob(json.dumps(out, ensure_ascii=False), overwrite=True)

    logging.info("Wrote metrics: %s/%s", OUT_CONTAINER, out_name)