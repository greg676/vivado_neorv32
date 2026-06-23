# ADS+MCP — Section 00: VISION

**Document ID:** ADS-00-VISION  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 0.1 What ADS+MCP Is

ADS+MCP is the **AI Design Studio debugger cockpit** — a project-agnostic workflow infrastructure built on Open WebUI custom models and four scoped MCP servers. It is the cockpit from which you build hardware products.

Any project plugs in by providing one file: `project.profile.json`. Swap the profile, switch the project. The infrastructure stays.

---

## 0.2 The Three Principles

### Principle 1 — OWUI is the sole human-facing cockpit
You sit in Open WebUI. OpenClaw steps back to orchestration, memory, and routing. All project debug interaction happens through R7 OWUI custom models with MCP tools.

### Principle 2 — Power comes from scoped tools, not raw access
Do not make one model powerful by giving it shell access to everything. Make four narrow MCP servers, each with bounded authority, audit logs, and safety gates.

### Principle 3 — Roles are fixed; brains are swappable
A custom model defines a role (system prompt + tools + permissions). Its base LLM is a dropdown you change anytime. Lock the roles. Never lock the models.

---

## 0.3 The Prime Directive

> The model never touches raw shell.  
> It calls named operations.  
> Named operations have bounded behavior.  
> Bounded behavior can be audited, confirmed, and rolled back.

Safety comes not from trusting the model, but from architecture that makes unsafe operations structurally impossible without explicit human confirmation.

---

## 0.4 The Cockpit Concept

```
┌──────────────────────────────────────────────────────────────┐
│ R7 OWUI — THE SOLE COCKPIT (port 8080)                       │
│ https://claw-studio.tail708254.ts.net:8445                   │
│                                                              │
│ ROLE MODELS (system prompt + tools + permissions):            │
│                                                              │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ ai-design-orchestrator ← YOU CHAT WITH THIS          │    │
│ │ role: hardware debug agent                           │    │
│ │ tools: ALL 4 MCP servers, write + hardware access    │    │
│ │ base: [swappable dropdown]                           │    │
│ └──────────────────────────────────────────────────────┘    │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ ai-design-critic ← reviewer                          │    │
│ │ role: devil's advocate, finds flaws                  │    │
│ │ tools: filesystem (ro), github (ro), browser (ro)    │    │
│ │ base: [swappable dropdown]                           │    │
│ └──────────────────────────────────────────────────────┘    │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ ai-design-archivist ← documentarian                  │    │
│ │ role: writes reports, updates KB                     │    │
│ │ tools: filesystem (ro), github (ro)                  │    │
│ │ base: [swappable dropdown]                           │    │
│ └──────────────────────────────────────────────────────┘    │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ ai-design-researcher ← read-only scout (optional)    │    │
│ │ tools: filesystem (ro), github (ro), browser (ro)    │    │
│ └──────────────────────────────────────────────────────┘    │
│                                                              │
│ POOLED MODEL DROPDOWN:                                       │
│ *-r7 → 7900 XT 20GB (heavy local: 27B class)                │
│ *-r5 → 6600 8GB (exploration lab: ≤8B)                      │
│ *:cloud → no GPU (strong reasoning, OpenRouter)             │
│                                                              │
│ mcpo bridge → http://host.docker.internal:8200               │
│ ├── r7-filesystem-mcp                                       │
│ ├── github-project-mcp                                      │
│ ├── browser-puppeteer-mcp                                   │
│ └── hardware-debug-mcp                                      │
└──────────────────────────────────────────────────────────────┘
```

---

## 0.5 Success Criteria

- [ ] Orchestrator model in OWUI can call all four MCP tools
- [ ] Hardware state can be read without touching a terminal
- [ ] Codec register diffs against known-good are one click
- [ ] Dangerous operations require explicit human confirmation
- [ ] Every hardware operation is audit-logged
- [ ] Session artifacts are self-contained and KB-feedable
- [ ] Project swap is one profile file change

---

## 0.6 Document Relationships

```
00-VISION.md (this file)
    ↓ defines what it is
01-ENVIRONMENT.md
    ↓ defines hardware, storage, software baseline
02-PROJECT-PROFILE.md
    ↓ defines the keystone file
03-MODEL-LAYER.md
    ↓ defines roles, naming, GPU visibility
04-MCP-SERVERS.md
    ↓ defines the four servers
05-HARDWARE-DEBUG-MCP.md
    ↓ defines the custom server in detail
06-SAFETY-ARCHITECTURE.md
    ↓ defines tiers, audit, confirmation flow
07-INFRASTRUCTURE.md
    ↓ defines mcpo, data layout, session artifacts
08-BUILD-PLAN.md
    ↓ defines phases 0-6
09-OPENCLAW-TRANSITION.md
    ↓ defines legacy path
10-DECISIONS.md
    ↓ locked decisions
11-APPENDICES.md
    ↓ prompts, configs, runbooks
```

---

*End of Section 00 — VISION*
