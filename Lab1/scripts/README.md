# Lab1 — Entra setup scripts

PowerShell scripts provision Microsoft Entra objects for the [Lab1 sidecar stack](../sidecar/README.md). Run them **before** `docker compose` in `Lab1/sidecar/`.

## Prerequisites

- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation) (`Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`)
- `Connect-MgGraph` with permissions to create Agent ID blueprints and app registrations (see each script’s header)
- Entra roles appropriate for your tenant (e.g. Application Administrator for app registration work)

## Recommended order

### 1. Agent ID (Entra)

From this folder, run [entra-agent-blueprint-identity-setup.ps1](./entra-agent-blueprint-identity-setup.ps1) (requires `Connect-MgGraph` with Agent ID blueprint scopes).

Copy from the console output:

- Blueprint **client secret** (shown once)
- **Blueprint app id** (`Blueprint App ID`)
- **Agent app id** (`Agent App ID`)

```powershell
cd Lab1\scripts
.\entra-agent-blueprint-identity-setup.ps1 -TenantId '<tenant-guid>'
# Or omit names to use defaults: Lab1 Blueprint / Lab1 Agent + random suffix
```

### 2. Weather API (Entra)

Set `TENANT_ID` and `AGENT_CLIENT_ID` in [sidecar/.env](../sidecar/.env) (or pass `-TenantId` / `-AgentAppId`), then run [weather-api-setup.ps1](./weather-api-setup.ps1).

Copy the **Weather API app id** from the script summary.

```powershell
.\weather-api-setup.ps1
# Reads TENANT_ID and AGENT_CLIENT_ID from ..\sidecar\.env when omitted
```

### 3. Populate `.env` (bridge)

Complete [sidecar/.env](../sidecar/.env) from [sidecar/.env.example](../sidecar/.env.example):

| Variable | Source |
|----------|--------|
| `TENANT_ID` | Your Entra tenant |
| `BLUEPRINT_APP_ID` | Step 1 output |
| `BLUEPRINT_CLIENT_SECRET` | Step 1 output (secret text) |
| `AGENT_CLIENT_ID` | Step 1 output |
| `WEATHER_API_APP_ID` | Step 2 output |

Then start the stack from `Lab1/sidecar/` — see [sidecar README](../sidecar/README.md#quick-start).

## Scripts in this folder

| File | Purpose |
|------|---------|
| [entra-agent-blueprint-identity-setup.ps1](./entra-agent-blueprint-identity-setup.ps1) | Agent Identity blueprint, principal secret, Agent Identity |
| [weather-api-setup.ps1](./weather-api-setup.ps1) | Weather API app registration, `api://` URI, `Weather.Read` role, service principal, role assignment to agent |

## Security

Do not commit [sidecar/.env](../sidecar/.env) or script logs that contain blueprint client secrets.