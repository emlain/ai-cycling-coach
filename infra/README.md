# Infrastructure (Bicep)

Provisioning IaC delle risorse Azure necessarie al Coach AI.

> ⚠️ Skeleton — verrà popolato nello Sprint 1.

## Deploy (futuro)

```bash
az group create -n rg-aicc-dev -l westeurope
az deployment group create -g rg-aicc-dev -f main.bicep -p @parameters.dev.json
```

In futuro useremo `azd up` per il deploy completo (infra + code).
