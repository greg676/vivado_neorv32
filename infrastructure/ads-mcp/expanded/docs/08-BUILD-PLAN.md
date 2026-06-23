# ADS+MCP — Section 08: BUILD PLAN

**Document ID:** ADS-08-BUILD-PLAN  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 8.1 Phase 0 — Stabilize Foundation (NOW, ~15 min)

**Goal:** Make sure the OWUI foundation is solid before building on it.

### Milestones

| # | Task | Verification | Status |
|---|------|-------------|--------|
| 0.1 | Bump OWUI container nofile limit | `ulimit -n` shows 65536 | ☐ |
| 0.2 | Regenerate stale OWUI admin JWT token | API calls return 200 | ☐ |
| 0.3 | Document exact docker run command | Command saved with all mounts + env | ☐ |
| 0.4 | Confirm Tailscale URL access | `:8445` loads OWUI | ☐ |
| 0.5 | Confirm Ollama models on /mnt/data-1tb | `ollama list` shows models | ☐ |
| 0.6 | Confirm OWUI data on /mnt/data-1tb | DB, uploads, vector_db present | ☐ |
| 0.7 | Tag all R5 Ollama models with -r5 | `ollama list` on R5 shows *-r5 | ☐ |
| 0.8 | (Optional) Tag R7 Ollama models with -r7 | `ollama list` on R7 shows *-r7 | ☐ |

### Deliverables
- Working OWUI with correct nofile limit
- Fresh admin JWT token
- Documented docker run command
- All models tagged with GPU suffix

---

## 8.2 Phase 1 — Filesystem + GitHub MCP + Orchestrator (Days 1–3)

**Goal:** Prove the MCP→OWUI pipeline works end-to-end with safe tools.

### Milestones

| # | Task | Verification | Status |
|---|------|-------------|--------|
| 1.1 | Create `/mnt/data-1tb/ai-design-studio/` tree | Directory structure exists | ☐ |
| 1.2 | Create `project.profile.json` | Valid JSON, all placeholders filled | ☐ |
| 1.3 | Install + wrap filesystem MCP server | `fs.list` works from CLI | ☐ |
| 1.4 | Install + wrap GitHub MCP server | `github.issue.list` works from CLI | ☐ |
| 1.5 | Install mcpo | `mcpo --version` works | ☐ |
| 1.6 | Create mcpo config + systemd service | `systemctl --user status mcpo` shows running | ☐ |
| 1.7 | Register mcpo as Tool Server in OWUI | Tools appear in model config | ☐ |
| 1.8 | Create ai-design-orchestrator model | Model appears in OWUI dropdown | ☐ |
| 1.9 | Verify: list project files | Orchestrator returns file listing | ☐ |
| 1.10 | Verify: list GitHub issues | Orchestrator returns issue list | ☐ |

### Deliverables
- Full `/mnt/data-1tb/ai-design-studio/` tree
- `project.profile.json` with real values
- mcpo running as systemd service
- ai-design-orchestrator model in OWUI
- End-to-end tool call verified

---

## 8.3 Phase 2 — Browser MCP (Days 4–5)

**Goal:** Add headless browser capability.

### Milestones

| # | Task | Verification | Status |
|---|------|-------------|--------|
| 2.1 | Install Puppeteer MCP server | Server starts without errors | ☐ |
| 2.2 | Wrap with URL allowlist from profile | Blocked URL returns error | ☐ |
| 2.3 | Add to mcpo config | Tools appear in OWUI | ☐ |
| 2.4 | Verify: screenshot OWUI dashboard | Screenshot saved to captures dir | ☐ |
| 2.5 | Verify: extract text from docs page | Text extraction works | ☐ |

### Deliverables
- Browser MCP server running
- URL allowlist enforced
- Screenshots saving to correct dir

---

## 8.4 Phase 3 — Hardware MCP, Read-Only (Days 6–10)

**Goal:** Build the custom hardware server with safe read-only tools.

### Milestones

| # | Task | Verification | Status |
|---|------|-------------|--------|
| 3.1 | Build server skeleton + state machine | Server starts, state = DISCONNECTED | ☐ |
| 3.2 | Implement profile loading + identity check | `hw.identify()` returns board/probe info | ☐ |
| 3.3 | Implement `hw.status()` | Returns connected probes, board, UART, firmware | ☐ |
| 3.4 | Implement `hw.uart.tail()` | Returns last N lines of UART | ☐ |
| 3.5 | Implement `hw.rtt.read()` | Returns RTT buffer contents | ☐ |
| 3.6 | Implement `hw.codec.dump_registers()` | Returns all codec register values | ☐ |
| 3.7 | Implement `hw.codec.diff_known_good()` | Compares live vs known-good, reports diffs | ☐ |
| 3.8 | Implement `hw.i2c.scan()` | Returns I²C address map | ☐ |
| 3.9 | Implement `hw.jtag.detect()` | Returns JTAG chain | ☐ |
| 3.10 | Implement `hw.jlink.read_mem32()` + `read_regs()` | Returns memory/register values | ☐ |
| 3.11 | Wire JLink via pylink-square | Connection verified | ☐ |
| 3.12 | Wire UART via pyserial | Connection verified | ☐ |
| 3.13 | Build known-good register database | `profiles/tdm-8ch-known-good.json` exists | ☐ |
| 3.14 | Verify: `hw.codec.diff_known_good()` returns correct report | Live hardware matches or correctly reports diffs | ☐ |

### Deliverables
- `hardware-debug-mcp/server.py` with all Tier 0 tools
- Known-good register profile
- JLink + UART connections verified
- Read-only hardware tools working in OWUI

---

## 8.5 Phase 4 — Hardware MCP, Controlled Mutations (Days 11–14)

**Goal:** Add Tier 1 tools with confirmation flow.

### Milestones

| # | Task | Verification | Status |
|---|------|-------------|--------|
| 4.1 | Implement Tier 1 tools | All Tier 1 tools functional | ☐ |
| 4.2 | Implement confirmation flow | Model states reason, human confirms | ☐ |
| 4.3 | Implement state transitions | SAFE→DEBUG requires Tier 1 confirmation | ☐ |
| 4.4 | Implement checkpoint-before-mutation | Pre-mutation dump saved | ☐ |
| 4.5 | Implement audit log | All calls logged to audit.jsonl | ☐ |
| 4.6 | Verify: full codec register fix session | End-to-end: diagnose → propose → confirm → fix → verify | ☐ |

### Deliverables
- All Tier 1 tools working
- Confirmation flow operational
- State machine transitions enforced
- Audit log populated

---

## 8.6 Phase 5 — Hardware MCP, Dangerous Tier (Days 15–20)

**Goal:** Add Tier 2 tools with pending operation protocol.

### Milestones

| # | Task | Verification | Status |
|---|------|-------------|--------|
| 5.1 | Implement Tier 2 tools | All Tier 2 tools functional | ☐ |
| 5.2 | Implement pending operation protocol | Pending op returned, confirm/abort works | ☐ |
| 5.3 | Implement expiry (120s) | Expired op auto-aborts | ☐ |
| 5.4 | Implement smoke test runner | Named tests execute and report | ☐ |
| 5.5 | Implement RTT streaming capture | Burst capture works | ☐ |
| 5.6 | Implement JTAG breakpoint/step flow | Break, step, resume works | ☐ |
| 5.7 | Build session artifact system | Session dir auto-created with all artifacts | ☐ |
| 5.8 | Verify: firmware flash with full confirmation flow | End-to-end flash → verify → report | ☐ |

### Deliverables
- All Tier 2 tools with pending operation protocol
- Smoke test runner
- Session artifact system
- Full dangerous operation flow verified

---

## 8.7 Phase 6 — Critic + Archivist + Polish (Days 21–25)

**Goal:** Complete the model topology and harden.

### Milestones

| # | Task | Verification | Status |
|---|------|-------------|--------|
| 6.1 | Create ai-design-critic model | Model available in OWUI | ☐ |
| 6.2 | Create ai-design-archivist model | Model available in OWUI | ☐ |
| 6.3 | Curate KB with project docs | RAG returns relevant results | ☐ |
| 6.4 | (Optional) Automate orchestrator→critic API calls | Python tool calls critic model | ☐ |
| 6.5 | Run 5 real debug scenarios end-to-end | All pass | ☐ |
| 6.6 | Write operational runbook | Document saved to workspace/ | ☐ |

### Deliverables
- Critic + archivist models
- Curated knowledge base
- Operational runbook
- 5 verified debug scenarios

---

## 8.8 Timeline Summary

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

*End of Section 08 — BUILD PLAN*
