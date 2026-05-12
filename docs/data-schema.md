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
