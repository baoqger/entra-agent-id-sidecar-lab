# Lab2 — OBO (on-behalf-of)

Provisioning for the **MSAL.js client SPA**, blueprint permissions, and **Weather API OBO** used in the Lab1 sidecar chat UI.

## Run order

1. **Lab1** — blueprint, agent, Weather API app registration, and sidecar stack ([`entra-agent-id-setup.ipynb`](../Lab1/scripts/entra-agent-id-setup.ipynb) + [`Lab1/sidecar`](../Lab1/sidecar)).
2. **Lab2 OBO** — single notebook (three parts) or PowerShell:
   - **Notebook (recommended):** [`scripts/entra-agent-id-spa-client-setup.ipynb`](scripts/entra-agent-id-spa-client-setup.ipynb)
     - **Part 1** — client SPA ([`setup-obo-client-app.ps1`](scripts/setup-obo-client-app.ps1))
     - **Part 2** — blueprint URI, `access_as_user`, SPA API permission, admin consent Client SPA → Blueprint ([`setup-obo-blueprint.ps1`](scripts/setup-obo-blueprint.ps1) steps 1–4 and 6); `AGENT_CLIENT_ID` required; **step 5** (agent → Graph) skipped in notebook
     - **Part 3** — Weather delegated scope `weather.read` + agent → Weather admin consent ([`setup-weather-api-resource.ps1`](../Lab1/scripts/setup-weather-api-resource.ps1) steps **3b** and **6**); requires `WEATHER_API_APP_ID` from Lab1
     - **Not in notebook:** blueprint step 5 (agent → Graph); weather PS steps 3, 5, 7 (app role, assignment, `.env`)
   - **PowerShell only:**
     - `pwsh ./scripts/setup-obo-client-app.ps1 -TenantId '<tenant-guid>'`
     - `pwsh ./scripts/setup-obo-blueprint.ps1` with blueprint, agent, and client SPA app IDs
     - `pwsh ../Lab1/scripts/setup-weather-api-resource.ps1` for autonomous weather + full OBO resource setup

3. Copy **`CLIENT_SPA_APP_ID`** from Part 1 into [`Lab1/sidecar/.env`](../Lab1/sidecar/.env) and restart the stack for OBO sign-in in the chat UI.

Re-run **admin sign-in (device code)** in the notebook after pulling updates if new Graph scopes were added (`DelegatedPermissionGrant.ReadWrite.All` for Part 3).

See [`scripts/`](scripts/) for script headers and usage.
