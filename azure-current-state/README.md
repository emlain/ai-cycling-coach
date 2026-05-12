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
