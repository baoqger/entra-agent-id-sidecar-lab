# Entra Agent ID Sidecar Lab

Hands-on labs for securing AI agents with Microsoft Entra **Agent ID**: a sample LLM agent, the official **auth sidecar** (token acquisition and exchange), and a JWT-validating downstream API—covering how agents get **Agent Identity** tokens for API calls, including **autonomous (app-only)** and **on-behalf-of (OBO)** patterns supported by the sidecar.

## Who this is for

- **Agent and app developers** — See how to call tools and APIs without putting blueprint `client_secret`, MSAL, or token caching in your agent code.
- **Identity and platform engineers** — Get a runnable reference for the [Entra Agent ID auth sidecar](https://learn.microsoft.com/en-us/entra/msidweb/agent-id-sdk/overview) on Docker Compose, with a sample resource API that validates Agent Identity tokens.


## What this repository contains

This repo is a growing set of hands-on labs for **Entra Agent ID** and the **auth sidecar** pattern. Each lab is self-contained under its own `LabN/` folder.

Agents need **Agent Identity** tokens for downstream APIs. Blueprint credentials and token exchange belong in a **sidecar** in the same trust boundary as the agent—not in application code.

### Lab1 — Sidecar stack (available)

1. **[`Lab1/scripts/`](Lab1/scripts/)** — Jupyter notebook provisions blueprint, Agent Identity, and Weather API app registration in Entra via Microsoft Graph.
2. **[`Lab1/sidecar/`](Lab1/sidecar/)** — Docker Compose runs the official auth sidecar, a LangChain/Ollama sample agent, and a weather API that validates tokens.

**Start here for setup and runtime:** [`Lab1/sidecar/README.md`](Lab1/sidecar/README.md).

### Lab2 — (under development)

**Lab2** is in progress and will be added under `Lab2/` when it is ready. Check this section or the repository tree for updates.

## Repository layout

| Path | Purpose |
|------|---------|
| [`Lab1/scripts/`](Lab1/scripts/) | Entra setup notebook and Python dependencies |
| [`Lab1/sidecar/`](Lab1/sidecar/) | Compose stack, environment template, detailed lab docs |
| [`Lab1/sidecar/llm-agent/`](Lab1/sidecar/llm-agent/) | Sample agent and chat UI |
| [`Lab1/sidecar/weather-api/`](Lab1/sidecar/weather-api/) | Sample downstream API |

## Documentation map

| Topic | Where to read |
|-------|----------------|
| Workflow, architecture, quick start, troubleshooting | [`Lab1/sidecar/README.md`](Lab1/sidecar/README.md) |
| Entra provisioning | [`Lab1/scripts/entra-agent-id-setup.ipynb`](Lab1/scripts/entra-agent-id-setup.ipynb) |
| Downstream token validation | [`Lab1/sidecar/weather-api/README.md`](Lab1/sidecar/weather-api/README.md) |

## Security

Do not commit [`Lab1/sidecar/.env`](Lab1/sidecar/.env) or notebook outputs that contain secrets. This repo is **sample lab code**, not production guidance.

## Contributing

Issues and pull requests are welcome. Please keep changes focused and update the relevant README when behavior or setup steps change.

## Related Microsoft documentation

- [Entra Agent ID overview](https://learn.microsoft.com/en-us/entra/agent-id/overview-agent-id)
- [Create blueprint](https://learn.microsoft.com/en-us/entra/agent-id/create-blueprint)
- [Agent ID SDK / auth sidecar](https://learn.microsoft.com/en-us/entra/msidweb/agent-id-sdk/overview)
- [Auth sidecar security](https://learn.microsoft.com/en-us/entra/msidweb/agent-id-sdk/security)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for the full text.