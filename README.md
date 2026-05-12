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
