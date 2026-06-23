# ADS+MCP — Section 09: OPENCLAW TRANSITION

**Document ID:** ADS-09-OPENCLAW-TRANSITION  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 9.1 The Transition

The current OpenClaw codecbot (gateway 18793) is **not deleted** — it becomes a fallback/legacy path:

| Component | New Role |
|-----------|----------|
| **OWUI orchestrator** | Primary debug interface — where you sit and work |
| **OpenClaw codecbot** | Cron jobs (health checks, state verification), background archiving, webchat routing |
| **OpenClaw GodBot** | Orchestration, memory, multi-agent routing, planning work |

---

## 9.2 What Moves to OWUI

| Task | Current (OpenClaw) | Future (OWUI) |
|------|-------------------|---------------|
| Hardware debug | codecbot agent via sessions_spawn | ai-design-orchestrator with MCP tools |
| Code review | codecbot critic subagent | ai-design-critic (manual or automated) |
| Documentation | codecbot archivist subagent | ai-design-archivist |
| File inspection | exec cat/ls | fs.read / fs.list |
| GitHub operations | exec gh CLI | github-project MCP |
| Web UI inspection | Manual browser | browser-puppeteer MCP |

---

## 9.3 What Stays on OpenClaw

| Task | Why |
|------|-----|
| Discord/Signal/Telegram routing | OWUI doesn't do messaging |
| Cron jobs (health checks) | OpenClaw cron is reliable |
| Multi-agent orchestration | OpenClaw sessions_spawn is proven |
| Memory management | MEMORY.md, daily logs |
| Background archiving | Automated workspace maintenance |
| GodBot planning | Strategic project decisions |

---

## 9.4 The Gradual Scale-Down

Over time, as the OWUI path proves itself:

1. **Phase 0-3:** Both paths active. OWUI for interactive debug, OpenClaw for background.
2. **Phase 4-5:** OWUI becomes primary. OpenClaw codecbot scales to cron-only.
3. **Phase 6+:** OpenClaw codecbot may be fully retired if OWUI covers all needs.

**No rush.** The legacy path stays until the new path is proven.

---

## 9.5 OpenClaw Gateways (Current)

| Gateway | Port | Status |
|---------|------|--------|
| godbot | 18789 | Active — orchestration, memory |
| audio-companion | 18790 | Active — audiobot project |
| codecbot | 18793 | Active → transitioning to OWUI |
| greybot | 18794 | Active |
| blackbot | 18795 | Active |

---

*End of Section 09 — OPENCLAW TRANSITION*
