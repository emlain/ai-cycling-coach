# Data Schema

## Schema attuale: `daily-v2-coachready`

Generato dalla Function Python esistente, un file per workout.

### Top-level

| Field | Type | Description |
|---|---|---|
| `schema_version` | str | Es. `"daily-v2-coachready"` |
| `generated_utc` | ISO datetime | Quando è stato generato il file |
| `date` | date | Data dell'allenamento |
| `activity_id` | str | ID Strava |
| `source_blob` | str | Path del blob raw da cui deriva |
| `raw` | object | Dati grezzi Strava + Intervals |
| `coach_features` | object | Metriche derivate base |
| `laps_summary` | object | Aggregati sui lap |
| `intervals_detected` | array | Lap classificati come "intervallo" con zona |

### `raw.strava`
`id`, `date`, `name`, `type`, `distance_km`, `moving_time_min`,
`elevation`, `avg_power`, `avg_hr`, `suffer_score`

### `raw.intervals`
`fitness` (CTL), `fatigue` (ATL), `eftp`, `pMax`, `hrv_raw`,
`resting_hr_raw`, `sleep_hours_raw`, `sleep_score`, `steps`, `readiness`

### `coach_features`
`intensity_proxy`, `work_kj_proxy`, `ss_time_sec`, `vo2_time_sec`,
`training_load.{ctl,atl,tsb,atl_ctl_ratio}`, `efficiency.ef_daily`

### `laps_summary`
`laps_count`, `total_laps_time_sec`, `watts.{avg,min,max}`,
`hr.{avg,min,max}`, `cadence.{avg,min,max}`,
`time_in_zone_sec.{recovery,endurance,tempo,sweetspot,threshold,vo2,anaerobic,sprint}`

### `intervals_detected[]`
`lap_index`, `name`, `dur_sec`, `avg_watts`, `avg_hr`, `avg_cadence`,
`rel_ftp`, `zone`

---

## Schema proposto: `daily-v3-coachready`

Estende v2 con metriche di potenza "vere" e classificazione.

### Nuove sezioni

#### `power_metrics`
- `np` — Normalized Power (richiede stream Strava)
- `if` — Intensity Factor (NP/FTP)
- `tss` — Training Stress Score
- `vi` — Variability Index (NP/avg_power)
- `work_kj` — Lavoro totale (sostituisce work_kj_proxy)
- `best_efforts.{5s,15s,1min,5min,10min,20min,60min}`
- `decoupling_pct` — Pa:Hr drift seconda metà vs prima

#### `hr_metrics`
- `drift_pct` — drift HR nel workout

#### `workout_classification`
- `type`: `endurance` | `tempo` | `sweetspot` | `threshold` |
  `vo2max_intervals` | `anaerobic` | `recovery` | `race` | `mixed`
- `structured`: bool
- `confidence`: 0..1
- `primary_system`: `aerobic_base` | `tempo` | `threshold` | `vo2` | `anaerobic` | `neuromuscular`
- `execution_quality`: 0..1

#### `data_quality`
- `has_power`, `has_hr`, `has_stream`, `has_wellness`, `indoor`

#### `athlete_context`
- `ftp_used`, `weight_kg`, `age` (snapshot al momento)

#### `coach_notes_auto`
Array di stringhe — note generate automaticamente dal pre-processing.

---

## Athlete profile

File singolo `athlete/profile.json` (non committato). Schema in
[athlete/profile.example.json](../athlete/profile.example.json).

---

## Cosmos DB — collezioni proposte

| Collection | Partition key | Cosa contiene |
|---|---|---|
| `workouts` | `/athlete_id` | Un doc per workout (schema v3) |
| `daily_metrics` | `/athlete_id` | Un doc per giorno con CTL/ATL/TSB/load |
| `athlete_profile` | `/athlete_id` | Profilo atleta (singolo doc) |
| `chat_history` | `/athlete_id` | Cronologia conversazioni con il coach |
| `weekly_reports` | `/athlete_id` | Report generati automaticamente |

---

## Schema v3.1 (Sprint 1.2) — Strava enrichment

In aggiunta a v3, propaghiamo nuovi campi dal raw Strava attraverso `strava_history_lite.json`
e introduciamo un blob dedicato `athlete_profile.json`. La Function (PR #4b) li consumerà
producendo un nuovo blocco `activity_context` e arricchendo `athlete_context`
con `weight_kg`, `max_hr_observed`, `hr_zones` e metriche derivate `_per_kg`.

### `processed-data/strava_history_lite.json` — campi aggiunti

| Field | Type | Source |
|---|---|---|
| `sport_type` | string | Strava activity `sport_type` (es. `Ride`, `VirtualRide`, `GravelRide`, …) |
| `workout_type` | int\|null | 0/1/10/11/12/13 — per `Ride`, `1` = Race |
| `gear_id` | string\|null | ID bici Strava (es. `b17387028`) |
| `commute` | boolean | flag pendolarismo |
| `trainer` | boolean | flag indoor trainer (alternativa a `sport_type=VirtualRide`) |
| `max_hr` | number\|null | HR massimo dell'attività |
| `avg_cadence` | number\|null | cadenza media |
| `elapsed_time_min` | number | tempo totale (≠ moving_time) |
| `start_latlng` | [number,number]\|null | coordinate di partenza |

### `processed-data/athlete_profile.json` — nuovo blob

Pass-through diretto di `GET https://www.strava.com/api/v3/athlete` (scope `profile:read_all`).
Campi consumati dalla Function:

- `id` — athlete ID
- `weight` — peso in kg
- `ftp` — FTP Strava (cross-check con eFTP Intervals)
- `bikes[]` — array di `{id, name, primary, resource_state}`
- `shoes[]` — array di `{id, name}` (informativo)

Rigenerato ad ogni run di postino (overwrite). Snapshot del momento.

### `aggregator/YYYYMMDD_master_{id}.json` — schema esteso

Aggiunti i nuovi campi dentro `strava_data` (pass-through dal `_lite`) e un nuovo blocco
top-level `athlete_profile`.

```json
{
  "activity_id": "...",
  "strava_data": {
    "id": 18460723743,
    "date": "2026-05-11T06:40:46Z",
    "name": "Z2 short",
    "type": "VirtualRide",
    "sport_type": "VirtualRide",
    "workout_type": null,
    "gear_id": "b14855896",
    "commute": false,
    "trainer": true,
    "max_hr": 156,
    "avg_cadence": 90.9,
    "elapsed_time_min": 86,
    "start_latlng": null,
    "distance_km": 38.96,
    "moving_time_min": 85,
    "elevation": 392.4,
    "avg_power": 172.4,
    "avg_hr": 147.3,
    "suffer_score": 71
  },
  "intervals_data": { "...": "..." },
  "laps_data": [ "..." ],
  "athlete_profile": {
    "id": 107068614,
    "weight": 70.0,
    "ftp": 250,
    "bikes": [
      {"id": "b17387028", "name": "CCT EVO Pro", "primary": false},
      {"id": "b14855896", "name": "Look 566",    "primary": false}
    ]
  }
}
```

### Workflow dei deploy

- **PR #4a** (questa): modifiche solo a `azure-current-state/*.json` (Logic App definitions) + docs + template athlete.
  Function App **non toccata** — continua a girare ignorando i nuovi campi.
- **PR #4b** (prossima): modifiche alla Function per consumare i nuovi campi e produrre lo schema
  `daily-v3.1-coachready` con `activity_context`, `athlete_context` arricchito, `power_metrics._per_kg`,
  `best_efforts_per_kg`, `is_race`, `hr_zones`, `bike` resolution.