# ADS+MCP — Section 07: INFRASTRUCTURE

**Document ID:** ADS-07-INFRASTRUCTURE  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 7.1 The mcpo Bridge

mcpo bridges MCP stdio servers to an OpenAI-compatible tool API that OWUI consumes as a "Tool Server."

```
OWUI custom model
    │ tool call (OpenAI-compatible)
    ▼
mcpo (R7 host, port 8200)
    │ MCP protocol (stdio)
    ├── r7-filesystem-mcp
    ├── github-project-mcp
    ├── browser-puppeteer-mcp
    └── hardware-debug-mcp
```

**OWUI Tool Server URL:** `http://host.docker.internal:8200`
(OWUI runs in Docker; `host.docker.internal` resolves to the R7 host.)

---

## 7.2 mcpo Systemd Service

```ini
# ~/.config/systemd/user/mcpo.service
[Unit]
Description=mcpo MCP bridge for OWUI
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/mcpo \
  --config /mnt/data-1tb/ai-design-studio/mcp-servers/mcpo-config.json \
  --port 8200
Restart=on-failure
RestartSec=5
Environment=ADS_PROFILE=/mnt/data-1tb/ai-design-studio/project.profile.json

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now mcpo
systemctl --user status mcpo
```

---

## 7.3 mcpo Configuration

```json
{
  "mcpServers": {
    "r7-filesystem": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-filesystem-mcp.sh"
    },
    "github-project": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-github-mcp.sh"
    },
    "browser-puppeteer": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-browser-mcp.sh"
    },
    "hardware-debug": {
      "command": "/mnt/data-1tb/ai-design-studio/mcp-servers/run-hardware-mcp.sh"
    }
  }
}
```

---

## 7.4 Session Artifacts

Every conversation with the orchestrator produces a self-contained directory that feeds back into the KB:

```
/mnt/data-1tb/ai-design-studio/debug-sessions/
  2026-06-22-1035-codec-output-dead/
    ├── session.json              ← metadata: model, session ID, duration
    ├── conversation.md           ← human-readable transcript
    ├── hardware-audit.jsonl      ← every hardware operation
    ├── register-dumps/
    │   ├── 01-initial-dump.json
    │   ├── 02-post-reset-dump.json
    │   └── 03-post-config-dump.json
    ├── uart-captures/
    │   └── capture-01.txt
    ├── rtt-captures/
    │   └── rtt-01-driver-trace.txt
    ├── screenshots/
    │   └── owui-dashboard-01.png
    ├── proposed-fixes/
    │   └── codec-init.c.proposed.diff
    ├── applied-fixes/
    │   └── codec-init.c.applied.diff
    └── summary.md                ← model-generated debug report
```

---

## 7.5 Data Layout

```
/mnt/data-1tb/
├── ollama/models/                    ← Ollama blobs
├── open-webui/                       ← OWUI persistent data
│   ├── webui.db
│   ├── uploads/
│   ├── vector_db/
│   └── cache/
│
└── ai-design-studio/
    ├── project.profile.json          ← THE KEYSTONE
    ├── env/
    │   └── ads.env                   ← (mode 0600) secrets, tokens
    │
    ├── mcp-servers/                  ← Wrappers + mcpo config
    │   ├── run-filesystem-mcp.sh
    │   ├── run-github-mcp.sh
    │   ├── run-browser-mcp.sh
    │   ├── run-hardware-mcp.sh
    │   ├── mcpo-config.json
    │   └── start-mcpo.sh
    │
    ├── mcp/
    │   └── hardware-debug/
    │       └── server.py            ← THE CUSTOM SERVER (Phase 3-5)
    │
    ├── mcp-logs/                     ← Per-server logs
    │
    ├── audit/
    │   └── audit.jsonl              ← All tool calls
    │
    ├── workspace/                    ← Model system prompts, playbooks
    │   ├── ai-design-orchestrator-prompt.txt
    │   ├── ai-design-critic-prompt.txt
    │   ├── ai-design-archivist-prompt.txt
    │   └── ai-design-researcher-prompt.txt
    │
    ├── profiles/                     ← Known-good hardware states
    │   └── tdm-8ch-known-good.json
    │
    ├── knowledge/                    ← Curated markdown for RAG
    │   ├── register-maps/
    │   ├── datasheets/
    │   ├── playbooks/
    │   ├── openclaw/
    │   ├── openwebui/
    │   ├── ollama/
    │   └── project-docs/
    │
    ├── debug-sessions/               ← Session artifacts (auto-populated)
    ├── browser-captures/             ← Screenshots
    ├── artifacts/                    ← Traces, reports, bitstreams
    └── .trash/                       ← Safe delete target
```

---

## 7.6 OWUI Tool Server Registration

In OWUI Admin → Settings → Tools:

1. **Add Tool Server**
2. **URL:** `http://host.docker.internal:8200`
3. **Name:** `ADS+MCP Bridge`
4. **Save**

All four MCP servers' tools become available to any custom model with tools enabled.

---

*End of Section 07 — INFRASTRUCTURE*
