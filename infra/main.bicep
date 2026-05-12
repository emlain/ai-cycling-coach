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
