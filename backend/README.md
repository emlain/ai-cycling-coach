# Backend (Azure Functions, Python 3.11)

## Funzioni

- `ingest_function/` — Blob-triggered: legge JSON v2-coachready, calcola
  metriche derivate, salva su Cosmos DB.
- `api_function/` — HTTP-triggered: serve REST + chat AI.

## Run locale

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp local.settings.json.example local.settings.json
# modifica local.settings.json con le tue credenziali (NON committarlo)
func start
```

## Test

```bash
pytest ../tests -v
```
