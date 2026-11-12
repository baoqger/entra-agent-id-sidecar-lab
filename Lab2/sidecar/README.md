# Lab1 sidecar stack

Run from this directory:

```bash
cp .env.example .env   # fill values from entra-agent-id-setup notebook / PowerShell scripts
docker compose up --build -d
```

| Service | Source | Notes |
|---------|--------|--------|
| **sidecar** | `mcr.microsoft.com/entra-sdk/auth-sidecar` image | No local folder — configured in `docker-compose.yml` |
| **llm-agent** | [`llm-agent/`](llm-agent/) | Chat UI on http://localhost:3003 |
| **weather-api** | [`weather-api/`](weather-api/) | Downstream API sample |
| **ollama** | Official image (optional custom build in [`ollama/`](ollama/)) | Local LLM |

Details: [`llm-agent/README.md`](llm-agent/README.md).
