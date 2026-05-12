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
