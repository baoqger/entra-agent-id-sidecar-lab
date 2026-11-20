# Lab1 — Entra Agent ID sidecar stack

This folder runs a small **Docker Compose** lab that shows the **auth sidecar pattern** for Microsoft Entra **Agent ID**. The agent application never stores blueprint secrets or performs token exchange itself; it asks the sidecar for an `Authorization` header and then calls a downstream API.

This README describes the **autonomous (app-only)** path only: the chat UI runs in autonomous mode, with no signed-in user and no on-behalf-of (OBO) exchange.

## What you are proving

End to end, a LangGraph-style agent can:

1. Decide to call a tool (weather lookup).
2. Obtain an **Agent Identity token (TR)** from the Entra auth sidecar.
3. Call a downstream API that **cryptographically validates** that token.

If validation succeeds, the response includes real weather from Open-Meteo. If the sidecar or Entra configuration is wrong, the weather API returns `401` and the UI shows where the flow broke.

## Components

| Container | Role in the autonomous flow |
|-----------|-----------------------------|
| **llm-agent** | Flask chat UI + LangChain agent. Host port **3003**. Holds **no** blueprint client secret. |
| **sidecar** | `mcr.microsoft.com/entra-sdk/auth-sidecar` — client credentials as the **blueprint** app, mints **TR** for the configured **agent** app id. **Not published to the host** (in-cluster only). |
| **weather-api** | Sample downstream API. Validates `Bearer` JWT (signature, issuer, audience, agent claims). |
| **ollama** | Local LLM for tool-calling demos (optional for understanding the identity path; weather still hits the real API). |

## Scripts (`Lab1/scripts`) and this sidecar stack

The **`sidecar/`** folder is only the **runtime**: containers, sample agent, and sample downstream API. It does **not** create anything in Microsoft Entra. That work lives in **`Lab1/scripts/`** — PowerShell setup scripts (`entra-agent-blueprint-identity-setup.ps1`, `weather-api-setup.ps1`).

Think of two layers:

| Layer | Location | What it does |
|-------|----------|----------------|
| **Tenant setup** | `Lab1/scripts/` | Graph calls to create the blueprint, blueprint secret, Agent Identity, and Weather API app registration; prints IDs you need later. |
| **Runtime lab** | `Lab1/sidecar/` (this folder) | Reads those IDs from `.env` and runs Docker Compose so the sidecar can mint tokens and the agent can call `weather-api`. |

**Order matters.** Do not run `docker compose` first and then try to invent `.env` values by hand—the sidecar and `weather-api` will fail token and audience checks until Entra matches your setup output.

### Recommended workflow

1. **Agent ID (Entra)** — From `Lab1/scripts/`, run [`entra-agent-blueprint-identity-setup.ps1`](../../Lab1/scripts/entra-agent-blueprint-identity-setup.ps1) (requires `Connect-MgGraph` with Agent ID blueprint scopes). Copy the **blueprint client secret**, **blueprint app id**, and **agent app id** from the console output.

2. **Weather API (Entra)** — Set `TENANT_ID` and `AGENT_CLIENT_ID` in Lab1 [`sidecar/.env`](../../Lab1/sidecar/.env) (or pass `-TenantId` / `-AgentAppId`), then run [`weather-api-setup.ps1`](../../Lab1/scripts/weather-api-setup.ps1). Copy the **Weather API app id** from the summary.

3. **Populate `.env` (bridge)** — Complete Lab1 [`sidecar/.env`](../../Lab1/sidecar/.env) from [`.env.example`](.env.example): `TENANT_ID`, `BLUEPRINT_APP_ID`, `BLUEPRINT_CLIENT_SECRET`, `AGENT_CLIENT_ID`, `WEATHER_API_APP_ID`.

4. **Sidecar stack (Docker)** — From this folder (`Lab2/sidecar/`), run `docker compose up`. Containers read `.env` only.

```
Lab1/scripts/*.ps1                    Lab1/sidecar/.env  →  Lab2/sidecar/
         │                                                    │
         │  Microsoft Graph                                     │
         ▼                                                    │
   Entra tenant objects                                       │
         │                                                    │
         │  you copy IDs + secret                             │
         └───────────────────────────────────────────────────►│  docker compose
```

If you re-run the PowerShell scripts and create new apps, update `.env` again, then `docker compose up`.

## Sidecar pattern (why it exists)

```
┌─────────────────────────────────────────────────────────────────┐
│  Trust boundary (e.g. same pod / same Docker network)            │
│                                                                  │
│  ┌──────────────┐    HTTP (no secret)     ┌──────────────────┐  │
│  │  llm-agent   │ ──────────────────────► │  auth sidecar    │  │
│  │  (agent app) │   "Give me a header     │  (blueprint app  │  │
│  │              │    for weather-app"     │   + secret)      │  │
│  └──────┬───────┘                         └────────┬─────────┘  │
│         │                                          │             │
│         │  Bearer TR                               │  Entra ID   │
│         ▼                                          ▼             │
│  ┌──────────────┐                         (token mint / exchange) │
│  │ weather-api  │                                                  │
│  └──────────────┘                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Division of responsibility**

| Concern | Agent (`llm-agent`) | Sidecar |
|--------|---------------------|---------|
| Blueprint `client_secret` | Never | Held in env / compose |
| MSAL, JWKS, token cache | Never | Handled by sidecar |
| Which agent identity to use | Passes `AgentIdentity=<AGENT_CLIENT_ID>` | Uses blueprint to obtain TR for that agent |
| HTTP call to business API | Yes, with returned header | No |

That split is the point of the lab: agent code stays ordinary application logic; identity specialists operate one sidecar image the same way across hosts and clouds.

## Autonomous token flow

When the user asks for weather, the tool path in `llm-agent/app.py` runs roughly as follows.

```mermaid
sequenceDiagram
    participant User
    participant LLM as llm-agent
    participant Ollama
    participant Sidecar as auth sidecar
    participant Entra as Microsoft Entra ID
    participant API as weather-api

    User->>LLM: Chat message (e.g. weather in Seattle)
    LLM->>Ollama: Plan / tool call
    Ollama-->>LLM: get_weather(Seattle)
    LLM->>Sidecar: GET /AuthorizationHeaderUnauthenticated/weather-app?AgentIdentity={AGENT_CLIENT_ID}
    Sidecar->>Entra: Client credentials (blueprint) + agent token request
    Entra-->>Sidecar: Agent Identity token (TR)
    Sidecar-->>LLM: authorizationHeader (Bearer TR)
    LLM->>API: GET /weather?city=Seattle + Authorization
    API->>Entra: JWKS validate JWT
    API-->>LLM: JSON weather payload
    LLM-->>User: Natural language answer
```

**Tokens (autonomous only)**

| Label | Meaning in this lab |
|-------|---------------------|
| **Blueprint app** | Entra app registration with the client secret used only inside the sidecar (`BLUEPRINT_APP_ID`, `BLUEPRINT_CLIENT_SECRET`). |
| **Agent app** | The Agent Identity your tool represents (`AGENT_CLIENT_ID`). Passed on every sidecar request as `AgentIdentity`. |
| **TR** | Access token returned to the agent and sent to `weather-api`. Audience should match `api://<WEATHER_API_APP_ID>`. |

The UI’s debug panel labels these steps (tool call → sidecar → API) so you can correlate logs with Entra sign-in and API logs.

## How Compose wires autonomous mode

In `docker-compose.yml`, the sidecar downstream API name **`weather-app`** must match what the agent requests in code:

- Agent: `.../AuthorizationHeaderUnauthenticated/weather-app?AgentIdentity=...`
- Sidecar: `DownstreamApis__weather-app__BaseUrl`, `DownstreamApis__weather-app__Scopes__0=api://${WEATHER_API_APP_ID}/.default`, and `DownstreamApis__weather-app__RequestAppToken=true` for app-only token acquisition.

`weather-api` sets `EXPECTED_AUDIENCE=api://${WEATHER_API_APP_ID}` so `aud` on **TR** matches the custom API you registered with `weather-api-setup.ps1`.

The sidecar has **no `ports:` mapping** on purpose — see [Agent ID SDK security guidance](https://learn.microsoft.com/en-us/entra/msidweb/agent-id-sdk/security). Only `llm-agent` talks to it on `http://sidecar:5000` inside `agent-network-dev`.

## Quick start

After you complete the [scripts → `.env` → Compose workflow](#scripts-lab1scripts-and-this-sidecar-stack) above:

From **`Lab1/sidecar/`**:

```bash
cp .env.example .env
# Fill in values after running Lab1/scripts/*.ps1

docker compose up --build -d
```

Open **http://localhost:3003**, keep **Autonomous** selected, and ask for weather in a supported city (see [`weather-api/app.py`](weather-api/app.py) for the city list).

Useful checks:

```bash
docker compose ps
docker compose logs -f llm-agent sidecar weather-api
```

## Environment variables (autonomous minimum)

| Variable | Used by | Purpose |
|----------|---------|---------|
| `TENANT_ID` | sidecar, weather-api, llm-agent | Entra tenant |
| `BLUEPRINT_APP_ID` | sidecar | Client id for blueprint client credentials |
| `BLUEPRINT_CLIENT_SECRET` | sidecar | Blueprint secret (never pass to llm-agent) |
| `AGENT_CLIENT_ID` | llm-agent → sidecar query | Agent Identity app id |
| `WEATHER_API_APP_ID` | sidecar scopes, weather-api `EXPECTED_AUDIENCE` | Custom API registration for the sample |

See [`.env.example`](.env.example) for the full template.

## Deeper dives

- Downstream validation and claims: [`weather-api/README.md`](weather-api/README.md)
- Agent UI, tools, and implementation: [`llm-agent/`](llm-agent/) (`app.py`, `templates/`)

## Troubleshooting (autonomous)

| Symptom | Likely cause |
|---------|----------------|
| Sidecar errors in `llm-agent` debug log | Wrong blueprint secret, agent not linked to blueprint, or `AGENT_CLIENT_ID` mismatch |
| `401` from weather-api | `WEATHER_API_APP_ID` / audience drift between `.env`, sidecar scopes, and `EXPECTED_AUDIENCE` |
| Agent never calls the tool | Ollama not ready or model not pulled; check `ollama` logs |
| Connection refused to sidecar | Compose network issue; confirm `SIDECAR_URL=http://sidecar:5000` in llm-agent |

For first-time issues, finish the `Lab1/scripts` setup and confirm `.env` matches script output before debugging containers.