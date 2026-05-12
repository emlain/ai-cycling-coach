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
