# Lab2 — Entra setup scripts (OBO)

PowerShell scripts provision Microsoft Entra for the [Lab2 sidecar stack](../sidecar/README.md): Agent Identity, Weather API (delegated OBO), MSAL client SPA, and blueprint `access_as_user` for on-behalf-of through the auth sidecar.

Run these **before** `docker compose` in `Lab2/sidecar/`.

Use a **separate** Entra setup from Lab1 (`Lab2/sidecar/.env`, not `Lab1/sidecar/.env`). Lab1 provisions app roles for autonomous tokens; Lab2 adds delegated scopes, an MSAL SPA, and blueprint `access_as_user` for OBO.

## Prerequisites

- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/installation) (`Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`)
- Ability to create app registrations and grant admin consent (Application Administrator or equivalent)
- Copy [`../sidecar/.env.example`](../sidecar/.env.example) to [`../sidecar/.env`](../sidecar/.env) and set at least `TENANT_ID` before step 2

## Run order

```powershell
cd Lab2\scripts
```

### 1. Agent Identity blueprint + agent

[entra-agent-blueprint-identity-setup.ps1](./entra-agent-blueprint-identity-setup.ps1)

Creates the Agent ID blueprint (with client secret) and Agent Identity. Default names: `Lab2 Blueprint` / `Lab2 Agent` plus a random suffix.

```powershell
.\entra-agent-blueprint-identity-setup.ps1 -TenantId '<tenant-guid>'
```

Copy into [`../sidecar/.env`](../sidecar/.env):

| Variable | From output |
|----------|-------------|
| `TENANT_ID` | Your tenant (if not already set) |
| `BLUEPRINT_APP_ID` | Blueprint App ID |
| `BLUEPRINT_CLIENT_SECRET` | Client secret (shown once) |
| `AGENT_CLIENT_ID` | Agent App ID |

### 2. Weather API (OBO delegated scope)

[weather-api-setup.ps1](./weather-api-setup.ps1)

Registers the custom Weather API resource, adds delegated scope `weather.read`, creates the service principal, and grants admin consent **Agent → Weather API**.

Requires `TENANT_ID` and `AGENT_CLIENT_ID` in `.env` (or pass `-TenantId` / `-AgentAppId`).

```powershell
.\weather-api-setup.ps1
```

Add to `.env`:

| Variable | From output |
|----------|-------------|
| `WEATHER_API_APP_ID` | Weather API App ID |

### 3. Client SPA (MSAL sign-in)

[client-spa-setup.ps1](./client-spa-setup.ps1)

Creates the browser SPA app used for user sign-in (`http://localhost:3003` redirect by default). Default display name: `Agent Client SPA` + random suffix.

```powershell
.\client-spa-setup.ps1
```

Add to `.env`:

| Variable | From output |
|----------|-------------|
| `CLIENT_SPA_APP_ID` | Client SPA App ID (printed at end) |

### 4. Blueprint OBO (`access_as_user`)

[client-blueprint-obo-setup.ps1](./client-blueprint-obo-setup.ps1)

Configures the **blueprint** as an API with delegated scope `access_as_user`, wires the Client SPA to request it, and grants admin consent **Client SPA → Blueprint**.

Requires in `.env`: `TENANT_ID`, `BLUEPRINT_APP_ID`, `AGENT_CLIENT_ID`, `CLIENT_SPA_APP_ID` (or pass the same as script parameters).

```powershell
.\client-blueprint-obo-setup.ps1
```

After all four steps, start the stack from [`Lab2/sidecar/`](../sidecar/) — see [sidecar README](../sidecar/README.md).

## Flow (high level)

```text
 1 entra-agent-blueprint-identity-setup  →  blueprint + agent + secret
 2 weather-api-setup                     →  Weather API + OBO scope + agent consent
 3 client-spa-setup                      →  MSAL SPA app
 4 client-blueprint-obo-setup            →  blueprint access_as_user + SPA consent
         │
         └─►  ../sidecar/.env  ──►  docker compose (OBO + sidecar)
```

## Scripts in this folder

| File | Purpose |
|------|---------|
| [entra-agent-blueprint-identity-setup.ps1](./entra-agent-blueprint-identity-setup.ps1) | Blueprint, secret, Agent Identity |
| [weather-api-setup.ps1](./weather-api-setup.ps1) | Weather API app, `weather.read`, SP, OBO grant to agent |
| [client-spa-setup.ps1](./client-spa-setup.ps1) | Client SPA registration, redirect URI, SP |
| [client-blueprint-obo-setup.ps1](./client-blueprint-obo-setup.ps1) | Blueprint API for OBO, SPA permissions, admin consent |

## Reference

OBO blueprint pattern: [Entra Agent ID — Part 2 (Christian Posta)](https://blog.christianposta.com/entra-agent-id-agw/PART-2.html)

## Security

Do not commit [`../sidecar/.env`](../sidecar/.env) or logs that contain blueprint client secrets.