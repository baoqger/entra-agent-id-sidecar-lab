# Lab2 — OBO (on-behalf-of)

Provisioning for the **MSAL.js client SPA** and blueprint permissions used in the OBO flow.

## Run order

1. **Lab1** — blueprint, agent, and sidecar stack (`entra-agent-id-setup.ipynb` + `Lab1/sidecar`).
2. **Lab2 OBO** — single notebook (both parts) or PowerShell:
   - **Notebook (recommended):** [`scripts/entra-agent-id-spa-client-setup.ipynb`](scripts/entra-agent-id-spa-client-setup.ipynb)
     - **Part 1** — client SPA (`setup-obo-client-app.ps1`)
     - **Part 2** — blueprint URI, `access_as_user`, SPA API permission, admin consent Client SPA → Blueprint (`setup-obo-blueprint.ps1` steps 1–4 and 6); requires `AGENT_CLIENT_ID` for script parity and step 5 checks (agent → Graph consent not automated in notebook)
     - **Not in notebook:** admin consent for Agent Identity → Microsoft Graph (PowerShell step 5); use `setup-obo-blueprint.ps1` or the portal if needed
   - **PowerShell only:**
     - `pwsh ./scripts/setup-obo-client-app.ps1 -TenantId '<tenant-guid>'`
     - `pwsh ./scripts/setup-obo-blueprint.ps1` with blueprint, agent, and client SPA app IDs

3. Copy **`CLIENT_SPA_APP_ID`** from Part 1 into [`Lab1/sidecar/.env`](../Lab1/sidecar/.env) and restart the stack for OBO sign-in in the chat UI.

See [`scripts/`](scripts/) for script headers and usage.
