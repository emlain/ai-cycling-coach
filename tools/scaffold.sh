#!/usr/bin/env bash
# AI Cycling Coach — Sprint 0 scaffold
# Run from the root of a fresh clone of emlain/ai-cycling-coach
set -euo pipefail

echo "🚴 Scaffolding AI Cycling Coach (Sprint 0)..."

# Branch
git checkout -b scaffold/sprint-0 2>/dev/null || git checkout scaffold/sprint-0

# Directories
mkdir -p docs azure-current-state infra backend/ingest_function backend/api_function \
         backend/shared frontend athlete tests \
         .github/workflows .github/ISSUE_TEMPLATE tools

# --- .gitignore ---
cat > .gitignore <<'EOF'
# Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/
.pytest_cache/
.ruff_cache/
.mypy_cache/

# Azure Functions
local.settings.json
bin/
obj/

# Node / Frontend
node_modules/
dist/
build/
.vite/

# Env / secrets
.env
.env.*
!.env.example

# Personal data — NEVER commit
/data/
/workouts/
/exports/
athlete/profile.json

# Artifacts
*.bacpac
*.zip

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
!.vscode/settings.json.example
.idea/
EOF

# --- LICENSE (MIT) ---
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026 emlain

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
EOF

# --- README ---
cat > README.md <<'EOF'
# 🚴 AI Cycling Coach

Un **coach virtuale AI** per ciclisti agonistici amatoriali, costruito interamente su **Azure**.
Analizza gli allenamenti provenienti da **Strava** e **Intervals.icu**, individua pattern e
crisi, e propone come migliorare la performance — tramite una **dashboard web** e una
**chat AI** che conosce la tua storia di allenamento.

## 🎯 Vision

Avere un assistente che ogni settimana risponda a domande come:
- "Come è andato il blocco di soglia delle ultime 2 settimane?"
- "Sto migliorando in VO2max?"
- "Sono in overreaching? Devo scaricare?"
- "Che lavori dovrei fare nelle prossime 3 settimane in vista della granfondo del 15 agosto?"

Tutto basato sui **tuoi dati reali**, con metriche da coach professionista (NP, IF, TSS, decoupling,
best efforts, training load).

## 🏗️ Architettura

```
┌────────────────────┐
│ Strava / Intervals │
└──────────┬─────────┘
           ▼
┌────────────────────┐       ┌─────────────────────────┐
│ Logic App (esiste) │──────▶│ Azure Blob Storage      │
│ ingest + merge     │       │ 1 JSON per workout      │
└────────────────────┘       └────────────┬────────────┘
                                          │ (Blob trigger)
                                          ▼
                  ┌─────────────────────────────────────────┐
                  │ Azure Function (Python) — INGEST        │
                  │ • parse JSON v2-coachready              │
                  │ • compute metrics (NP/IF/TSS/decoupling)│
                  │ • upsert in Cosmos DB                   │
                  └────────────────────┬────────────────────┘
                                       ▼
                  ┌─────────────────────────────────────────┐
                  │ Azure Cosmos DB (workouts + athlete)    │
                  └────────────────────┬────────────────────┘
                                       ▼
                  ┌─────────────────────────────────────────┐
                  │ Azure Function — API (HTTP)             │
                  │ • REST: /workouts /trends /best-efforts │
                  │ • /chat → Azure OpenAI + RAG            │
                  └────────────────────┬────────────────────┘
                                       ▼
                  ┌─────────────────────────────────────────┐
                  │ 🌐 Azure Static Web App                 │
                  │ • Dashboard + Chat Coach AI             │
                  │ • Auth via Entra ID                     │
                  └─────────────────────────────────────────┘
```

Dettagli completi: [docs/architecture.md](./docs/architecture.md)

## 🧰 Stack tecnologico

| Layer | Tecnologia |
|---|---|
| Ingest esistente | Azure Logic Apps |
| Storage raw | Azure Blob Storage |
| Compute backend | Azure Functions (Python 3.11) |
| Database | Azure Cosmos DB (serverless) |
| AI | Azure OpenAI (gpt-4o-mini) |
| Search/RAG | Cosmos vector search (Sprint 2+) |
| Frontend | React + Vite + TypeScript + Recharts |
| Hosting frontend | Azure Static Web Apps |
| Auth | Microsoft Entra ID |
| IaC | Bicep |
| CI | GitHub Actions |

## 📁 Struttura del repository

```
ai-cycling-coach/
├── README.md
├── docs/
│   ├── architecture.md         # Architettura dettagliata + costi
│   ├── data-schema.md          # Schema v2 attuale + v3 proposto
│   └── azure-resources.md      # Inventario Azure da compilare
├── azure-current-state/        # Export Logic App + codice Function esistente
├── infra/                      # Bicep IaC (placeholder)
├── backend/                    # Azure Functions Python
│   ├── ingest_function/
│   ├── api_function/
│   └── shared/                 # models, metrics, prompts
├── frontend/                   # Static Web App (Sprint 3)
├── athlete/                    # Profilo atleta (template)
├── tests/                      # Test + fixtures
├── tools/                      # Script di utility
└── .github/                    # CI/CD + templates
```

## 🗺️ Roadmap

- ✅ **Sprint 0** — Scaffold del progetto (questo PR)
- 🔜 **Sprint 1** — Inventario Azure attuale + Function ingest verso Cosmos + metriche NP/IF/TSS
- 🔜 **Sprint 2** — API HTTP + integrazione Azure OpenAI + primo coach AI funzionante
- 🔜 **Sprint 3** — Frontend Static Web App (dashboard + chat)
- 🔜 **Sprint 4** — Report settimanale automatico, alert overreaching, confronto trend

## 🚀 Getting started

> ⚠️ Non c'è ancora nulla da eseguire — questo è solo lo scaffold. Le istruzioni
> reali arriveranno con lo Sprint 1.

```bash
# Clona
git clone https://github.com/emlain/ai-cycling-coach.git
cd ai-cycling-coach

# Setup ambiente Python (per il backend, quando ci sarà)
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r backend/requirements.txt
```

## 🔒 Cosa va / cosa NON va in questo repo

✅ **SÌ**
- Codice (Python, TypeScript)
- Infrastructure as Code (Bicep)
- Schema di dati, documentazione
- Esempi e template con valori finti
- Prompt del coach AI

❌ **NO — MAI**
- Connection string Azure
- API key (Strava, Intervals.icu, OpenAI)
- Dati reali di workout (`/data/`, `/workouts/`)
- Profilo atleta reale (`athlete/profile.json` — solo `.example.json`)
- File `.env` o `local.settings.json` reali

I segreti useranno **GitHub Secrets** in CI e **Azure Key Vault** in runtime,
con **Managed Identity** dove possibile.

## 🤝 Contributi

Vedi [CONTRIBUTING.md](./CONTRIBUTING.md).

## 📜 Licenza

[MIT](./LICENSE)
EOF

# --- CONTRIBUTING ---
cat > CONTRIBUTING.md <<'EOF'
# Contributing

## Branch naming

- `feat/<short-description>` — nuove funzionalità
- `fix/<short-description>` — bug fix
- `docs/<short-description>` — solo documentazione
- `chore/<short-description>` — manutenzione, build, CI
- `scaffold/<sprint>` — scaffold dei vari sprint

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) consigliato:

```
feat(backend): add NP and IF computation
fix(ingest): handle missing wellness fields
docs: update architecture diagram
chore(ci): bump python to 3.12
```

## Pull Requests

- Titolo conciso ma descrittivo
- Descrizione: cosa cambia, perché, come testarlo
- Linka issue correlate con `Closes #N`
- Squash merge preferito per mantenere `main` lineare

## Code style

- Python: `ruff` per lint + format (configurato in CI)
- TS: prettier + eslint (verrà aggiunto con il frontend)
- Type hints OBBLIGATORI sul codice Python di produzione
EOF

# --- docs/architecture.md ---
cat > docs/architecture.md <<'EOF'
# Architettura

## Componenti

| Componente | Ruolo | Sizing consigliato | Costo stimato (EUR/mese) |
|---|---|---|---|
| Logic App (esistenti) | Ingest Strava + Intervals.icu | Consumption | ~€0 |
| Blob Storage | JSON raw e v2-coachready | LRS, Hot | < €1 |
| Function App (Python) | Ingest blob→Cosmos + API HTTP | Consumption (Y1) | < €1 |
| Cosmos DB | workouts, daily_metrics, athlete | Serverless | €1–5 |
| Azure OpenAI | LLM per il coach | gpt-4o-mini | €2–10 |
| Static Web App | Frontend | Free tier | €0 |
| Key Vault | Segreti runtime | Standard | < €0.50 |
| Application Insights | Logging/telemetria | Pay-as-you-go (basico) | < €1 |

**Totale stimato uso personale**: ~€5–15/mese.

## Flusso 1: Ingestion di un workout

```mermaid
sequenceDiagram
    participant L as Logic App
    participant B as Blob Storage
    participant F as Function (ingest)
    participant C as Cosmos DB

    L->>B: Scrive 20260429_master_*.json (v2-coachready)
    B-->>F: Blob trigger
    F->>F: Parse + valida (Pydantic)
    F->>F: Calcola NP/IF/TSS/decoupling
    F->>C: Upsert workout doc
    F->>C: Update daily_metrics aggregate
```

## Flusso 2: Chat con il Coach AI (RAG)

```mermaid
sequenceDiagram
    participant U as User
    participant W as Static Web App
    participant A as API Function
    participant C as Cosmos DB
    participant O as Azure OpenAI

    U->>W: "Come è andato il blocco soglia?"
    W->>A: POST /chat {message, history}
    A->>C: Query workouts recenti + athlete profile
    A->>A: Costruisce prompt: profile + workouts + question
    A->>O: Chat completion
    O-->>A: Risposta coach
    A-->>W: {answer, citations[]}
    W-->>U: Visualizza con citazioni
```

## Sicurezza

- **Nessun segreto nel repo**: `.gitignore` blocca `.env`, `local.settings.json`, profili reali
- **Runtime secrets**: in Azure Key Vault, referenziati via Managed Identity
- **Auth utente**: Microsoft Entra ID su Static Web App
- **Auth tra servizi**: Managed Identity (Function → Cosmos, Function → OpenAI, Function → Blob)
- **CORS**: ristretto al dominio della Static Web App
- **Network**: per uso personale tutto pubblico con auth; eventualmente Private Endpoints in v2

## Decisioni architetturali (ADR)

### ADR-001: Perché Cosmos DB e non SQL?
- Schema-flexible (lo schema dei workout evolverà)
- Serverless con consumi ridotti
- Supporto a vector search per il RAG futuro

### ADR-002: Perché gpt-4o-mini?
- Rapporto qualità/prezzo ottimo per il task (analisi tabellare/numerica)
- Latenza bassa per UX chat fluida
- Possibilità di switchare a gpt-4o per le review settimanali "lunghe" se serve qualità extra
EOF

# --- docs/data-schema.md ---
cat > docs/data-schema.md <<'EOF'
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
EOF

# --- docs/azure-resources.md ---
cat > docs/azure-resources.md <<'EOF'
# Inventario Azure attuale

> 📋 **Da compilare**: questo documento serve a fotografare lo stato delle risorse Azure
> già esistenti, così possiamo allinearci prima di costruire i nuovi componenti.

## Resource Group

| Name | Location | Note |
|---|---|---|
| `<NOME_RG>` | `<region>` | |

## Logic Apps

| Name | Trigger | Purpose | Blobs read | Blobs written |
|---|---|---|---|---|
| `<logicapp-1>` | | Ingest Strava + Intervals | | |
| `<logicapp-2>` | | Merge in master JSON | | |

## Function Apps

| Name | Runtime | Triggers | Purpose |
|---|---|---|---|
| `<funcapp-existing>` | Python 3.x | Blob | Produce daily-v2-coachready |

## Storage Accounts

| Name | Containers | Purpose |
|---|---|---|
| `<storage-account>` | `aggregator`, `<altro>` | |

## Key Vaults

| Name | Secrets stored | Consumed by |
|---|---|---|
| | | |

## Entra ID App Registrations

| Name | Purpose | Redirect URIs |
|---|---|---|
| | Strava OAuth | |
| | Intervals.icu | |

---

## Comandi `az` per raccogliere l'inventario

Esegui in Cloud Shell e copia gli output qui sotto.

```bash
RG=<NOME_RG>

# Tutte le risorse del RG
az resource list -g $RG -o table > rg-resources.txt

# Logic Apps
az logic workflow list -g $RG -o json > logic-apps.json

# Function Apps
az functionapp list -g $RG \
  --query "[].{Name:name, Runtime:siteConfig.linuxFxVersion, State:state}" \
  -o table > function-apps.txt

# Storage
az storage account list -g $RG --query "[].name" -o tsv > storage-accounts.txt

# Per ciascuno storage account, lista i container:
# az storage container list --account-name <name> --auth-mode login -o table
```

---

## Export delle Logic App

Per ogni Logic App: Portal → **Export Template** → `template.json` → carica
in [`/azure-current-state/`](../azure-current-state/).

⚠️ **REDIGI i segreti** prima di committare (connection string, API key Strava,
client secret OAuth, ecc.). Sostituiscili con `<REDACTED>`.
EOF

# --- azure-current-state/README ---
cat > azure-current-state/README.md <<'EOF'
# Azure current state

Caricare qui:

1. **Logic App templates** — Portal Azure → Logic App → Export Template
   - File: `logicapp-<purpose>.template.json`
2. **Function App source** — codice Python esistente
   - Folder: `function-app-existing/`
3. **Eventuali Bicep/ARM** già usati per il provisioning

## ⚠️ Sicurezza

Prima di committare, **redigi sempre**:
- Connection string (`DefaultEndpointsProtocol=...AccountKey=...`)
- API key (Strava `client_secret`, Intervals.icu API key)
- OAuth secret
- SAS token

Sostituisci con `<REDACTED>` o `${PARAMETER_NAME}`.
EOF
touch azure-current-state/.gitkeep

# --- infra/main.bicep ---
cat > infra/main.bicep <<'EOF'
// AI Cycling Coach — Infrastructure as Code (Bicep)
// Sprint 0: skeleton only. Da popolare durante Sprint 1.

targetScope = 'resourceGroup'

@description('Name prefix for all resources')
param namePrefix string = 'aicc'

@description('Azure region')
param location string = resourceGroup().location

@description('Environment tag')
param environment string = 'dev'

// TODO: Storage account (riusare l'esistente? oppure nuovo container)
// TODO: Cosmos DB serverless
//   - account
//   - database 'coach'
//   - containers: workouts, daily_metrics, athlete_profile, chat_history
// TODO: Azure OpenAI
//   - account
//   - deployment gpt-4o-mini
//   - deployment text-embedding-3-small (per RAG futuro)
// TODO: Key Vault + access policies / RBAC
// TODO: Function App (Python 3.11)
//   - App Service Plan consumption (Y1)
//   - System-assigned Managed Identity
//   - Role assignments su Cosmos, OpenAI, Key Vault, Storage
// TODO: Static Web App (frontend)
// TODO: Application Insights + Log Analytics workspace
// TODO: Output: endpoint URLs, function name, ecc.
EOF

cat > infra/parameters.example.json <<'EOF'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "namePrefix": { "value": "aicc" },
    "environment": { "value": "dev" }
  }
}
EOF

cat > infra/README.md <<'EOF'
# Infrastructure (Bicep)

Provisioning IaC delle risorse Azure necessarie al Coach AI.

> ⚠️ Skeleton — verrà popolato nello Sprint 1.

## Deploy (futuro)

```bash
az group create -n rg-aicc-dev -l westeurope
az deployment group create -g rg-aicc-dev -f main.bicep -p @parameters.dev.json
```

In futuro useremo `azd up` per il deploy completo (infra + code).
EOF

# --- backend/requirements.txt ---
cat > backend/requirements.txt <<'EOF'
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
azure-cosmos>=4.5.1
azure-identity>=1.15.0
azure-keyvault-secrets>=4.7.0
openai>=1.12.0
pydantic>=2.5.0
python-dotenv>=1.0.0
EOF

# --- backend/host.json ---
cat > backend/host.json <<'EOF'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": { "isEnabled": true, "excludedTypes": "Request" }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
EOF

# --- backend/local.settings.json.example ---
cat > backend/local.settings.json.example <<'EOF'
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsStorage": "<STORAGE_CONNECTION_STRING>",
    "COSMOS_ENDPOINT": "<COSMOS_ENDPOINT_URL>",
    "COSMOS_KEY": "<COSMOS_KEY_OR_USE_MANAGED_IDENTITY>",
    "AZURE_OPENAI_ENDPOINT": "<OPENAI_ENDPOINT>",
    "AZURE_OPENAI_DEPLOYMENT": "gpt-4o-mini",
    "AZURE_OPENAI_API_VERSION": "2024-02-15-preview"
  }
}
EOF

# --- backend/README.md ---
cat > backend/README.md <<'EOF'
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
EOF

# --- backend/ingest_function ---
cat > backend/ingest_function/function.json <<'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "name": "myblob",
      "type": "blobTrigger",
      "direction": "in",
      "path": "coach-ready/{name}",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
EOF

cat > backend/ingest_function/__init__.py <<'EOF'
"""Blob-triggered ingest of v2-coachready workouts into Cosmos DB.

TODO (Sprint 1):
  - Parse blob bytes -> WorkoutV2 (Pydantic)
  - Compute derived metrics (NP, IF, TSS, VI, decoupling, best efforts)
  - Upsert into Cosmos workouts collection
  - Update daily_metrics aggregate
"""
from __future__ import annotations

import logging

import azure.functions as func


def main(myblob: func.InputStream) -> None:
    logging.info(
        "Blob trigger fired: name=%s size=%s bytes",
        myblob.name,
        myblob.length,
    )
    # TODO: implement ingest pipeline (Sprint 1)
    raise NotImplementedError("ingest_function not yet implemented")
EOF

cat > backend/ingest_function/README.md <<'EOF'
# ingest_function

Blob trigger sui file `coach-ready/*.json`.
Da implementare nello Sprint 1.
EOF

# --- backend/api_function ---
cat > backend/api_function/function.json <<'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get", "post"],
      "route": "{*path}"
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
EOF

cat > backend/api_function/__init__.py <<'EOF'
"""HTTP API for the AI Cycling Coach.

Planned routes (Sprint 2+):
  GET  /workouts?from=...&to=...
  GET  /workouts/{activity_id}
  GET  /trends?metric=ctl|atl|tsb
  GET  /best-efforts
  POST /chat   { message, history? } -> { answer, citations[] }
"""
from __future__ import annotations

import json
import logging

import azure.functions as func


def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("API request: %s %s", req.method, req.url)
    return func.HttpResponse(
        body=json.dumps({"status": "scaffold", "message": "API not yet implemented"}),
        mimetype="application/json",
        status_code=501,
    )
EOF

cat > backend/api_function/README.md <<'EOF'
# api_function

HTTP API per la dashboard e la chat coach.
Da implementare nello Sprint 2.
EOF

# --- backend/shared ---
cat > backend/shared/__init__.py <<'EOF'
"""Shared modules: data models, metric computations, coach prompts."""
EOF

cat > backend/shared/models.py <<'EOF'
"""Pydantic models for the daily-v2-coachready schema.

Faithfully represents the JSON produced by the existing ingest Function.
Used both by the ingest_function (validation) and the api_function (serialization).
"""
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
    ctl: float
    atl: float
    tsb: float
    atl_ctl_ratio: float | None = None


class Efficiency(BaseModel):
    ef_daily: float | None = None


class CoachFeatures(BaseModel):
    intensity_proxy: float | None = None
    work_kj_proxy: float | None = None
    ss_time_sec: int = 0
    vo2_time_sec: int = 0
    training_load: TrainingLoad
    efficiency: Efficiency = Field(default_factory=Efficiency)


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
    time_in_zone_sec: TimeInZoneSec = Field(default_factory=TimeInZoneSec)


class DetectedInterval(BaseModel):
    lap_index: int
    name: str
    dur_sec: int
    avg_watts: float
    avg_hr: float | None = None
    avg_cadence: float | None = None
    rel_ftp: float
    zone: Zone


class WorkoutV2(BaseModel):
    """Top-level model for schema_version = daily-v2-coachready."""
    model_config = ConfigDict(extra="allow")

    schema_version: str
    generated_utc: datetime
    date: date
    activity_id: str
    source_blob: str | None = None
    raw: RawSection
    coach_features: CoachFeatures
    laps_summary: LapsSummary
    intervals_detected: list[DetectedInterval] = Field(default_factory=list)
EOF

cat > backend/shared/metrics.py <<'EOF'
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
EOF

cat > backend/shared/coach_prompts.py <<'EOF'
"""LLM prompts for the AI Cycling Coach.

Prompts are written in Italian because the end user is Italian.
The coach persona is evidence-based, encouraging, technically rigorous.
"""
from __future__ import annotations

SYSTEM_PROMPT_COACH = """\
Sei un Coach di ciclismo agonistico, esperto in allenamento basato sui dati
(power-based training, metodologia Coggan/Friel/Seiler). Stai assistendo un
ciclista amatoriale di 40 anni che ha ripreso a correre da qualche anno dopo
aver concluso l'attività agonistica giovanile a 20 anni.

Caratteristiche dell'atleta:
- Ha 2 bici: una collegata ai rulli per allenamenti indoor, una outdoor per
  uscite e qualche gara
- Tracking via Strava + Intervals.icu, dati ingestati su Azure
- Vuole massimizzare la performance compatibilmente con vincoli di tempo
  e recupero da amatore

Linee guida per le tue risposte:
1. **Sii rigoroso ma non freddo**: cita le metriche (CTL, ATL, TSB, NP, IF, TSS,
   decoupling, time-in-zone) ma spiega sempre il significato pratico.
2. **Evidence-based**: se manca un dato (es. HRV, sonno), DICHIARALO esplicitamente
   invece di inventare. Non assumere mai dati che non hai.
3. **Personalizza**: tieni conto dell'età (40 anni → recupero più lento), del
   passato agonistico (buona base motoria), del fatto che è un amatore
   (vincoli di tempo).
4. **Concretezza > teoria**: dai sempre indicazioni operative (es. "prossimo
   workout: 3x12' SST a 88-92% FTP, 5' recupero").
5. **Sicurezza prima di tutto**: se vedi TSB molto negativo (< -25) o segnali
   di overreaching cronico, raccomanda riposo.
6. **Tono**: italiano corretto, professionale ma caldo. Niente emoji
   se non in chiusura o per enfasi puntuale.
7. **Citazioni**: quando ti baso su workout specifici, cita data e nome
   dell'allenamento.

Formato risposta consigliato (quando appropriato):
- **TL;DR** (1-2 frasi)
- **Cosa vedo nei dati** (bullet con metriche)
- **Cosa significa**
- **Cosa fare adesso** (azioni concrete)
- **Cosa monitorare** (segnali a cui prestare attenzione)
"""

RAG_USER_PROMPT_TEMPLATE = """\
[PROFILO ATLETA]
{athlete_profile}

[CONTESTO ALLENAMENTI RECENTI]
{workouts_context}

[STATO ATTUALE]
- CTL (fitness): {ctl}
- ATL (fatica): {atl}
- TSB (forma): {tsb}
- FTP corrente: {ftp} W
- Periodo: {period_start} → {period_end}

[DOMANDA DELL'ATLETA]
{user_question}

Rispondi seguendo le linee guida del system prompt.
"""

WEEKLY_REVIEW_PROMPT_TEMPLATE = """\
Genera la review settimanale per l'atleta basandoti sui workout della
settimana {week_start} → {week_end}.

[PROFILO]
{athlete_profile}

[WORKOUT DELLA SETTIMANA]
{weekly_workouts}

[METRICHE AGGREGATE]
- Volume totale (ore): {total_hours}
- TSS totale: {total_tss}
- Distribuzione zone (%): {zone_distribution}
- Variazione CTL vs settimana precedente: {ctl_delta}
- TSB di fine settimana: {tsb_end}

Genera una review strutturata:
1. **Sintesi esecutiva** (2-3 frasi)
2. **Cosa è andato bene**
3. **Cosa migliorare**
4. **Segnali da monitorare** (overreaching, decoupling, ecc.)
5. **Piano per la settimana prossima** (giorno per giorno, indicativo)
"""
EOF

# --- frontend placeholder ---
cat > frontend/README.md <<'EOF'
# Frontend — Azure Static Web App

Da implementare nello Sprint 3.

## Stack previsto

- React 18 + Vite + TypeScript
- Recharts (o Chart.js) per i grafici
- MSAL React per Entra ID auth
- Fetch via funzione `api_function` (linkata automaticamente dalla Static Web App)

## Pagine previste

- **Dashboard** — CTL/ATL/TSB chart, ultimi workout, distribuzione zone
- **Workouts** — lista filtrabile + dettaglio per workout
- **Trends** — curva di potenza, evoluzione FTP, decoupling nel tempo
- **Chat Coach** — chat con AI + cronologia
- **Profilo** — gestione dati atleta, obiettivi, zone
EOF
touch frontend/.gitkeep

# --- athlete profile example ---
cat > athlete/profile.example.json <<'EOF'
{
  "_comment": "EXAMPLE — copy to profile.json (gitignored) and replace with your real data",
  "athlete_id": "example-athlete",
  "birth_date": "1985-09-18",
  "weight_kg": 72,
  "height_cm": 178,
  "ftp_history": [
    {"date": "2026-04-01", "ftp_watts": 255, "source": "intervals_eftp"},
    {"date": "2026-04-29", "ftp_watts": 258, "source": "intervals_eftp"}
  ],
  "max_hr": 190,
  "resting_hr_baseline": 48,
  "hr_zones": [
    {"name": "Z1", "min_bpm": 0,   "max_bpm": 130},
    {"name": "Z2", "min_bpm": 130, "max_bpm": 150},
    {"name": "Z3", "min_bpm": 150, "max_bpm": 165},
    {"name": "Z4", "min_bpm": 165, "max_bpm": 178},
    {"name": "Z5", "min_bpm": 178, "max_bpm": 190}
  ],
  "power_zones_pct_ftp": {
    "recovery":  [0,   55],
    "endurance": [55,  75],
    "tempo":     [75,  90],
    "sweetspot": [88,  94],
    "threshold": [94,  105],
    "vo2":       [105, 120],
    "anaerobic": [120, 150],
    "sprint":    [150, 999]
  },
  "goals": [
    {"event_name": "Granfondo Example",
     "event_date": "2026-08-15",
     "priority": "A",
     "type": "granfondo",
     "distance_km": 150,
     "elevation_m": 3000}
  ],
  "bikes": [
    {"id": "indoor", "name": "Indoor trainer", "usage": "indoor"},
    {"id": "road",   "name": "Road bike",      "usage": "outdoor"}
  ],
  "training_constraints": {
    "weekly_hours_target": 8,
    "available_days": ["mon","tue","wed","thu","fri","sat","sun"],
    "preferred_long_ride_day": "sun"
  },
  "background": {
    "previous_career": "Ex agonista 14-20 anni, rientro a 36 anni",
    "current_level": "Amateur competitive"
  }
}
EOF

# --- tests ---
cat > tests/__init__.py <<'EOF'
EOF

cat > tests/sample_workout_v2.json <<'EOF'
{
  "schema_version": "daily-v2-coachready",
  "generated_utc": "2026-05-07T16:17:47.201745+00:00",
  "date": "2026-04-29",
  "activity_id": "18302280862",
  "source_blob": "aggregator/20260429_master_18302280862.json",
  "raw": {
    "strava": {
      "id": 18302280862,
      "date": "2026-04-29T06:08:44Z",
      "name": "Progressive zones climb",
      "type": "VirtualRide",
      "distance_km": 30.1133,
      "moving_time_min": 63,
      "elevation": 299.0,
      "avg_power": 183.7,
      "avg_hr": 156.9,
      "suffer_score": 72.0
    },
    "intervals": {
      "date": "2026-04-29",
      "fitness": 45.72694,
      "fatigue": 53.91994,
      "eftp": 258.0,
      "pMax": 969.3432,
      "hrv_raw": 0.0,
      "resting_hr_raw": 0.0,
      "sleep_hours_raw": 0.0,
      "sleep_score": 0.0,
      "steps": 0,
      "readiness": 0.0
    }
  },
  "coach_features": {
    "intensity_proxy": 0.7120155038759689,
    "work_kj_proxy": 694.386,
    "ss_time_sec": 180,
    "vo2_time_sec": 60,
    "training_load": {
      "ctl": 45.72694,
      "atl": 53.91994,
      "tsb": -8.192999999999998,
      "atl_ctl_ratio": 1.179172277873831
    },
    "efficiency": { "ef_daily": 1.1708094327597194 }
  },
  "laps_summary": {
    "laps_count": 15,
    "total_laps_time_sec": 3601,
    "watts":   { "avg": 183.83, "min": 118.0, "max": 303.9 },
    "hr":      { "avg": 158.76, "min": 130.6, "max": 181.0 },
    "cadence": { "avg": 85.48,  "min": 61.2,  "max": 101.9 },
    "time_in_zone_sec": {
      "recovery": 961, "endurance": 900, "tempo": 1260,
      "sweetspot": 180, "threshold": 240, "vo2": 60,
      "anaerobic": 0, "sprint": 0
    }
  },
  "intervals_detected": [
    {"lap_index": 6, "name": "Lap 6", "dur_sec": 60,
     "avg_watts": 303.9, "avg_hr": 181.0, "avg_cadence": 75.1,
     "rel_ftp": 1.178, "zone": "vo2"},
    {"lap_index": 5, "name": "Lap 5", "dur_sec": 180,
     "avg_watts": 260.8, "avg_hr": 177.4, "avg_cadence": 82.1,
     "rel_ftp": 1.011, "zone": "threshold"}
  ]
}
EOF

cat > tests/test_models.py <<'EOF'
"""Validate that the sample v2-coachready JSON parses cleanly."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from shared.models import WorkoutV2  # noqa: E402


def test_sample_workout_parses() -> None:
    sample_path = Path(__file__).parent / "sample_workout_v2.json"
    data = json.loads(sample_path.read_text())
    wk = WorkoutV2.model_validate(data)

    assert wk.schema_version == "daily-v2-coachready"
    assert wk.activity_id == "18302280862"
    assert wk.laps_summary.laps_count == 15
    assert len(wk.intervals_detected) == 2
    assert wk.intervals_detected[0].zone == "vo2"
    assert wk.coach_features.training_load.tsb < 0
EOF

# --- pyproject for ruff/pytest config ---
cat > pyproject.toml <<'EOF'
[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "N", "RUF"]
ignore = ["E501"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["backend"]
EOF

# --- CI workflows ---
cat > .github/workflows/ci.yml <<'EOF'
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
          cache: pip
      - name: Install deps
        run: |
          python -m pip install --upgrade pip
          pip install -r backend/requirements.txt
          pip install ruff pytest
      - name: Lint
        run: ruff check backend tests
      - name: Format check
        run: ruff format --check backend tests
      - name: Tests
        run: pytest -v
EOF

cat > .github/workflows/codeql.yml <<'EOF'
name: CodeQL

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: "0 6 * * 1"

jobs:
  analyze:
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      actions: read
      contents: read
    strategy:
      fail-fast: false
      matrix:
        language: [ python ]
    steps:
      - uses: actions/checkout@v4
      - uses: github/codeql-action/init@v3
        with:
          languages: ${{ matrix.language }}
      - uses: github/codeql-action/analyze@v3
EOF

# --- Issue templates ---
cat > .github/ISSUE_TEMPLATE/sprint-task.md <<'EOF'
---
name: Sprint task
about: Task del backlog di sprint
labels: ["sprint"]
---

## Obiettivo

<!-- Cosa vogliamo ottenere e perché -->

## Acceptance criteria

- [ ] ...
- [ ] ...

## Note tecniche

<!-- Riferimenti a docs, decisioni architetturali, dipendenze -->
EOF

cat > .github/ISSUE_TEMPLATE/coach-feedback.md <<'EOF'
---
name: Coach AI feedback
about: Feedback sulla qualità delle risposte del Coach AI
labels: ["coach-feedback", "prompt-tuning"]
---

## Domanda fatta al coach

> ...

## Risposta ricevuta

> ...

## Cosa funziona

- ...

## Cosa NON funziona

- ...

## Suggerimento di miglioramento prompt / dati

- ...
EOF

# --- tools/ ---
cat > tools/README.md <<'EOF'
# Tools

Script di utility per il progetto.

- `scaffold.sh` — Script di scaffolding iniziale (Sprint 0). Già eseguito.
EOF

# Copy this script into tools/ for posterity
if [ -f scaffold.sh ]; then
  cp scaffold.sh tools/scaffold.sh
fi

echo "✅ Scaffold complete!"
echo ""
echo "Next steps:"
echo "  git add ."
echo "  git commit -m 'feat: Sprint 0 — project scaffold'"
echo "  git push -u origin scaffold/sprint-0"
echo "  # Then open a PR on GitHub from scaffold/sprint-0 → main"