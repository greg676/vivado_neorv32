# ADS+MCP — AI Design Studio Cockpit
## Expanded Implementation Documentation

**Version 1.0 — Implementation Ready**  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## What This Is

The complete step-by-step implementation documentation for the ADS+MCP debugger cockpit — a project-agnostic workflow infrastructure built on Open WebUI custom models and four scoped MCP servers.

This is the expanded companion to `ADS+MCP.md` (the master architecture opus).

---

## Document Set

| # | Document | Description |
|---|----------|-------------|
| 00 | [VISION](docs/00-VISION.md) | What ADS+MCP is, the three principles, the prime directive |
| 01 | [ENVIRONMENT](docs/01-ENVIRONMENT.md) | Hardware inventory, storage, software baseline, Phase 0 prerequisites |
| 02 | [PROJECT PROFILE](docs/02-PROJECT-PROFILE.md) | The keystone file — complete schema, field reference, project swap |
| 03 | [MODEL LAYER](docs/03-MODEL-LAYER.md) | Single cockpit, naming convention, role models, GPU visibility, 8GB reality |
| 04 | [MCP SERVERS](docs/04-MCP-SERVERS.md) | All four servers — tools, safety rules, implementation, mcpo config |
| 05 | [HARDWARE DEBUG MCP](docs/05-HARDWARE-DEBUG-MCP.md) | The custom server — state machine, tool tiers, RTT, confirmation flow, skeleton code |
| 06 | [SAFETY ARCHITECTURE](docs/06-SAFETY-ARCHITECTURE.md) | Unified tier model, audit log, identity lock, checkpoints, emergency stop |
| 07 | [INFRASTRUCTURE](docs/07-INFRASTRUCTURE.md) | mcpo bridge, systemd service, session artifacts, data layout |
| 08 | [BUILD PLAN](docs/08-BUILD-PLAN.md) | Phases 0-6 with milestones, deliverables, timeline |
| 09 | [OPENCLAW TRANSITION](docs/09-OPENCLAW-TRANSITION.md) | Legacy path, what moves, what stays, gradual scale-down |
| 10 | [DECISIONS](docs/10-DECISIONS.md) | All 17 locked decisions with rationale |
| 11 | [APPENDICES](docs/11-APPENDICES.md) | System prompts, service files, wrapper scripts, quick reference |

---

## Quick Start

### For the person building this:
1. Start with [01-ENVIRONMENT](docs/01-ENVIRONMENT.md) — verify Phase 0 prerequisites
2. Then [08-BUILD-PLAN](docs/08-BUILD-PLAN.md) — follow phases in order
3. Reference [02-PROJECT-PROFILE](docs/02-PROJECT-PROFILE.md) when creating the keystone file
4. Reference [05-HARDWARE-DEBUG-MCP](docs/05-HARDWARE-DEBUG-MCP.md) when building the custom server

### For understanding the architecture:
1. [00-VISION](docs/00-VISION.md) — the why
2. [03-MODEL-LAYER](docs/03-MODEL-LAYER.md) — the model topology
3. [04-MCP-SERVERS](docs/04-MCP-SERVERS.md) — the tool layer
4. [06-SAFETY-ARCHITECTURE](docs/06-SAFETY-ARCHITECTURE.md) — the safety model

---

## The Prime Directive

> The model never touches raw shell.  
> It calls named operations.  
> Named operations have bounded behavior.  
> Bounded behavior can be audited, confirmed, and rolled back.

---

## Build Timeline

```
Phase 0: Foundation      █ (~15 min)     NOW
Phase 1: Filesystem+Git  ████            Days 1-3
Phase 2: Browser         ██              Days 4-5
Phase 3: HW Read-Only    █████           Days 6-10
Phase 4: HW Mutations    ████            Days 11-14
Phase 5: HW Dangerous    ██████          Days 15-20
Phase 6: Polish           █████           Days 21-25

Total: ~4 weeks to full cockpit
MVP (Phase 0-3): ~2 weeks — read-only hardware debug working
```

---

*End of README*
