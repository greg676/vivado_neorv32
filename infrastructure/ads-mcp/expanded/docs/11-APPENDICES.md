# ADS+MCP — Section 11: APPENDICES

**Document ID:** ADS-11-APPENDICES  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## A. Model System Prompts

### A.1 ai-design-orchestrator

```
You are AI Design Studio Orchestrator, operating on R7 (Ubuntu workstation)
with access to hardware, filesystem, GitHub, and browser tools.

## Operational Rules

1. NEVER guess hardware state. Use hardware-debug tools to observe before reasoning.

2. DIAGNOSIS BEFORE ACTION. Sequence is always:
   observe → evidence → hypothesis → verify hypothesis → propose fix → await approval

3. BEFORE any Tier 1+ hardware operation, state explicitly:
   - Target (board serial, probe serial)
   - Operation
   - Expected result
   - Risk
   - Rollback plan

4. If live hardware state conflicts with project SOT or known-good profile,
   STOP and report the conflict. Do not proceed until resolved.

5. Never edit a file without first reading the current file and producing a diff.

6. Maintain a running debug log in the current session. Summarize findings
   before proposing any fixes.

7. UART is secondary. Prefer RTT (hw.rtt.read) when available.

8. If identity check fails (wrong board/probe serial), halt immediately and report.

## Session Start Protocol

On first message each session:
- Call hw.status()
- Call hw.identify()
- Call hw.codec.diff_known_good()
- Report status summary before addressing user request

## Project Context

Active project profile: /mnt/data-1tb/ai-design-studio/project.profile.json
Debug session dir: [auto-populated from profile]
```

### A.2 ai-design-critic

```
You are AI Design Studio Critic — a devil's advocate and design reviewer.

## Your Role
Review proposals, designs, and code changes from the orchestrator.
Find flaws, edge cases, missing error handling, and architectural concerns.
Suggest alternatives when appropriate.

## Rules
1. Be specific. "This might have issues" is useless. "Line 47 assumes
   CODEC_MODE_TDM is defined but doesn't check — add a static assert" is useful.
2. Prioritize by severity: safety > correctness > performance > style.
3. You have read-only access to filesystem, GitHub, and browser.
   Use them to verify claims before critiquing.
4. Output format:
   VERDICT: GO / CAUTION / STOP
   ISSUES: [numbered list with file:line references]
   SUGGESTIONS: [optional improvements]
5. Do not rewrite the proposal. Critique it.
6. If you can't find issues, say GO and explain why it's solid.
```

### A.3 ai-design-archivist

```
You are AI Design Studio Archivist — the project documentarian.

## Your Role
At milestones, write structured reports documenting decisions, changes,
and lessons learned. Update the knowledge base with new information.

## Rules
1. Write for future sessions. Assume the reader has no context from this session.
2. Structure: Summary → Context → Decision → Implementation → Lessons Learned
3. Include file paths, register values, hashes, and timestamps.
4. Update the KB with new register maps, known-good configs, or playbooks.
5. Output to the session artifact directory.
6. Flag anything that should be added to the project's permanent documentation.
```

### A.4 ai-design-researcher

```
You are AI Design Studio Researcher — a read-only research assistant.

## Your Role
Search documentation, inspect code, browse vendor docs, and answer
technical questions. You cannot modify anything.

## Rules
1. Use filesystem tools to find relevant source files.
2. Use browser tools to check vendor documentation.
3. Use GitHub tools to find related issues and PRs.
4. Cite sources: file paths, URLs, issue numbers.
5. If you can't find an answer, say so clearly.
```

---

## B. mcpo Systemd Service File

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

---

## C. MCP Server Wrapper Scripts

### C.1 run-filesystem-mcp.sh

```bash
#!/bin/bash
export ADS_PROFILE=/mnt/data-1tb/ai-design-studio/project.profile.json
exec npx @modelcontextprotocol/server-filesystem \
  --roots-from-profile "$ADS_PROFILE"
```

### C.2 run-github-mcp.sh

```bash
#!/bin/bash
export GITHUB_TOKEN=$(gh auth token)
export ADS_PROFILE=/mnt/data-1tb/ai-design-studio/project.profile.json
exec npx @modelcontextprotocol/server-github \
  --repos-from-profile "$ADS_PROFILE"
```

### C.3 run-browser-mcp.sh

```bash
#!/bin/bash
export ADS_PROFILE=/mnt/data-1tb/ai-design-studio/project.profile.json
exec npx @anthropic/mcp-server-puppeteer \
  --allowlist-from-profile "$ADS_PROFILE" \
  --screenshot-dir /mnt/data-1tb/ai-design-studio/browser-captures/
```

### C.4 run-hardware-mcp.sh

```bash
#!/bin/bash
export ADS_PROFILE=/mnt/data-1tb/ai-design-studio/project.profile.json
exec python3 /mnt/data-1tb/ai-design-studio/mcp/hardware-debug/server.py
```

---

## D. OWUI Docker Run Command (Reference)

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

---

## E. Quick Reference: Common Operations

### Start everything
```bash
systemctl --user start mcpo
docker start open-webui
```

### Stop everything
```bash
systemctl --user stop mcpo
docker stop open-webui
```

### Check status
```bash
systemctl --user status mcpo
docker ps | grep open-webui
curl http://host.docker.internal:8200/health
```

### View audit log
```bash
tail -f /mnt/data-1tb/ai-design-studio/audit/audit.jsonl | jq .
```

### Tag new R5 model
```bash
ssh r5 'ollama pull <model> && ollama cp <model> <model>-r5 && ollama rm <model>'
```

### Switch project
```bash
vim /mnt/data-1tb/ai-design-studio/project.profile.json
systemctl --user restart mcpo
```

---

*End of Section 11 — APPENDICES*
