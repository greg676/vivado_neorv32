# ADS+MCP — Section 01: ENVIRONMENT

**Document ID:** ADS-01-ENVIRONMENT  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 1.1 Hardware Inventory

| Machine | GPU | VRAM | Role in ADS+MCP |
|---------|-----|------|-----------------|
| R7 (gj-007, 10.0.0.50) | RX 7900 XT | 20GB | Primary cockpit + heavy local inference |
| R5 (gary, 10.0.0.231) | RX 6600 | 8GB | Small-model exploration lab + embeddings |
| Arty Z7-20 (10.0.0.245) | — | — | Codec hardware target |
| Kria KV260 (10.0.0.150) | — | — | Edge vision target |

---

## 1.2 Storage

| Drive | Size | Free | Purpose |
|-------|------|------|---------|
| nvme0n1 (/) | 465GB | ~107GB | OS, projects, OpenClaw workspaces |
| sdb1 (/mnt/data-1tb) | 931GB | ~800GB | All ADS+MCP data, Ollama models, OWUI data |

**Rule:** All ADS+MCP data, sessions, models, and KB live on `/mnt/data-1tb`. Config and code may symlink from elsewhere, but data lives on the big drive.

---

## 1.3 Software Baseline

| Component | Location | Status |
|-----------|----------|--------|
| OWUI v0.9.6 | R7 Docker, port 8080 | Running, data on /mnt/data-1tb |
| Ollama | R7 systemd, port 11434 | 16 models, 7900 XT |
| Ollama | R5 systemd, port 11434 | Small models + embeddings, 6600 |
| OpenClaw | R7, multiple gateways | GodBot, codecbot, audiobot, blackbot, greybot |
| Tailscale | Mesh across all machines | claw-studio.tail708254.ts.net |
| OpenRouter pipe | R7 OWUI | Cloud models imported |

---

## 1.4 Network

| URL | Port | Service |
|-----|------|---------|
| claw-studio.tail708254.ts.net | 8445 | R7 OWUI (cockpit) |
| gary-ms-7b87.tail708254.ts.net | 8445 | R5 OWUI (optional, not used by ADS+MCP) |
| 10.0.0.50 | 11434 | R7 Ollama |
| 10.0.0.231 | 11434 | R5 Ollama |
| 10.0.0.245 | 9090 | Arty Jupyter |
| 10.0.0.150 | 5000 | Kria dashboard |

---

## 1.5 R7 OWUI Docker Run Command

```bash
docker run -d \
  --name open-webui \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /mnt/data-1tb/open-webui:/app/backend/data \
  -v /mnt/data-1tb/ai-design-studio/knowledge:/app/backend/data/uploads \
  -e OLLAMA_BASE_URL=http://host.docker.internal:11434 \
  -e WEBUI_SECRET_KEY=<from-container> \
  --ulimit nofile=65536:65536 \
  ghcr.io/open-webui/open-webui:main
```

**Key mounts:**
- `/mnt/data-1tb/open-webui` → OWUI persistent data (DB, vector DB, cache)
- `/mnt/data-1tb/ai-design-studio/knowledge` → KB files accessible to OWUI

---

## 1.6 R5 Ollama Remote Connection

R7 OWUI connects to R5 Ollama as a remote backend. In OWUI Admin → Settings → Connections:

```
Ollama Base URL: http://10.0.0.231:11434
```

Or via Tailscale:
```
Ollama Base URL: http://100.119.22.28:11434
```

**Important:** R5 models must be tagged with `-r5` suffix to avoid name collisions with R7 models. See Section 03.

---

## 1.7 Phase 0 Prerequisites

Before any MCP work, stabilize the foundation:

1. **Bump OWUI container nofile limit** — currently 1024, ~896 FDs open. Set to 65536.
2. **Regenerate stale OWUI admin JWT token** — fresh login if needed.
3. **Document exact docker run command** with all mounts + env.
4. **Confirm Tailscale URL access** — `:8445` works from browser.
5. **Confirm Ollama models + OWUI data on /mnt/data-1tb** — verify paths.
6. **Tag all R5 Ollama models with -r5** — optionally tag R7 with -r7.

---

*End of Section 01 — ENVIRONMENT*
