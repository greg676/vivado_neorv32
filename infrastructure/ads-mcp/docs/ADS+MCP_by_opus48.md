# ADS+MCP
## AI Design Studio — Master Architecture Opus
### The definitive project document for the design infrastructure

**Project:** ADS+MCP — AI Design Studio Cockpit  
**Version:** 1.0 (Architecture Locked)  
**Date:** 2026-06-22  
**Host:** R7 (gj-007, 10.0.0.50)  
**Mesh:** claw-studio.tail708254.ts.net  
**Status:** Implementation Ready

---

## PART I — VISION

### 1. What ADS+MCP Is

ADS+MCP is the AI Design Studio debugger cockpit — a project-agnostic workflow infrastructure built on Open WebUI custom models and four scoped MCP servers. It is the cockpit from which you build hardware products.

Any project plugs in by providing one file: `project.profile.json`. Swap the profile, switch the project. The infrastructure stays.

### 2. The Three Principles

**Principle 1 — OWUI is the sole human-facing cockpit.**
You sit in Open WebUI. OpenClaw steps back to orchestration, memory, and routing. All project debug interaction happens through R7 OWUI custom models with MCP tools.

**Principle 2 — Power comes from scoped tools, not raw access.**
Do not make one model powerful by giving it shell access to everything. Make four narrow MCP servers, each with bounded authority, audit logs, and safety gates.

**Principle 3 — Roles are fixed; brains are swappable.**
A custom model defines a role (system prompt + tools + permissions). Its base LLM is a dropdown you change anytime. Lock the roles. Never lock the models.

### 3. The Prime Directive

> The model never touches raw shell.  
> It calls named operations.  
> Named operations have bounded behavior.  
> Bounded behavior can be audited, confirmed, and rolled back.

Safety comes not from trusting the model, but from architecture that makes unsafe operations structurally impossible without explicit human confirmation.

---

## PART II — THE ENVIRONMENT

### 4. Hardware Inventory

| Machine | GPU | VRAM | Role in ADS+MCP |
|---------|-----|------|-----------------|
| R7 (gj-007, 10.0.0.50) | RX 7900 XT | 20GB | Primary cockpit + heavy local inference |
| R5 (gary, 10.0.0.231) | RX 6600 | 8GB | Small-model exploration lab + embeddings |
| Arty Z7-20 (10.0.0.245) | — | — | Codec hardware target |
| Kria KV260 (10.0.0.150) | — | — | Edge vision target |

### 5. Storage

| Drive | Size | Free | Purpose |
|-------|------|------|---------|
| nvme0n1 (/) | 465GB | ~107GB | OS, projects, OpenClaw workspaces |
| sdb1 (/mnt/data-1tb) | 931GB | ~800GB | All ADS+MCP data, Ollama models, OWUI data |

**Rule:** all ADS+MCP data, sessions, models, and KB live on `/mnt/data-1tb`. Config and code may symlink from elsewhere, but data lives on the big drive.

### 6. Software Baseline

| Component | Location | Status |
|-----------|----------|--------|
| OWUI v0.9.6 | R7 Docker, port 8080 | Running, data on /mnt/data-1tb |
| Ollama | R7 systemd, port 11434 | 16 models, 7900 XT |
| Ollama | R5 systemd, port 11434 | Small models + embeddings, 6600 |
| OpenClaw | R7, multiple gateways | GodBot, codecbot, audiobot, blackbot, greybot |
| Tailscale | Mesh across all machines | claw-studio.tail708254.ts.net |
| OpenRouter pipe | R7 OWUI | Cloud models imported |

---

## PART III — THE KEYSTONE

### 7. The Project Profile

All four MCP servers load a shared `project.profile.json` at startup. This is what makes four servers a system instead of four disconnected tools. It binds them to the same project identity, hardware identity, filesystem roots, repos, and known-good state.

**Location:** `/mnt/data-1tb/ai-design-studio/project.profile.json`

```json
{
  "profile_version": "1",
  "project": {
    "name": "<active-project>",
    "version": "0.4.x",
    "session_dir": "/mnt/data-1tb/ai-design-studio/debug-sessions/",
    "workspace_dir": "/mnt/data-1tb/ai-design-studio/workspace/"
  },
  "filesystem": {
    "read_roots": [
      "~/projects/",
      "/mnt/data-1tb/ai-design-studio/",
      "~/.openclaw-godbot/workspace/",
      "~/.openclaw-codecbot/workspaces/codecbot/",
      "~/Downloads/"
    ],
    "write_roots": [
      "~/projects/<active-project>/",
      "/mnt/data-1tb/ai-design-studio/workspace/",
      "/mnt/data-1tb/ai-design-studio/debug-sessions/"
    ],
    "trash_dir": "/mnt/data-1tb/ai-design-studio/.trash"
  },
  "github": {
    "username": "<github-user>",
    "repos": ["<org>/<active-project>", "openclaw/openclaw"],
    "default_branch": "main",
    "read_only_by_default": true
  },
  "hardware": {
    "board": "Arty-Z7-20",
    "board_serial": "<serial>",
    "probe": {
      "type": "SEGGER-JLink",
      "serial": "<probe-serial>",
      "interface": "JTAG",
      "target_device": "<target>"
    },
    "codec": {
      "chip": "<codec-chip>",
      "i2c_addr": "0x48",
      "config_profile": "tdm-8ch"
    },
    "uart": {
      "port": "/dev/ttyUSB0",
      "baud": 115200
    },
    "rtt_enabled": true
  },
  "known_good": {
    "firmware_hash": "<sha256>",
    "bitstream_hash": "<sha256>",
    "codec_register_profile": "profiles/tdm-8ch-known-good.json"
  },
  "browser": {
    "screenshot_dir": "/mnt/data-1tb/ai-design-studio/browser-captures/",
    "url_allowlist": [
      "http://127.0.0.1:*",
      "http://localhost:*",
      "http://10.0.0.*",
      "http://192.168.*",
      "*.ts.net",
      "github.com",
      "docs.amd.com",
      "docs.xilinx.com"
    ]
  },
  "audit_log": "/mnt/data-1tb/ai-design-studio/audit/audit.jsonl"
}
```

---

## PART IV — THE MODEL LAYER

### 8. Single Cockpit Architecture

One OWUI instance on R7 is the cockpit. It pools both Ollama backends and all cloud models. You do not need a second OWUI — R7 OWUI already sees R5's models through the remote Ollama connection.

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
│ POOLED MODEL DROPDOWN (every entry is self-documenting):     │
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

### 9. The Naming Convention — GPU Visibility Through Names

R7 OWUI pools two Ollama backends. If the same model name exists on both, OWUI routes unpredictably and you can't tell which GPU you hit. The fix: **never duplicate names. Suffix everything.**

| Suffix | GPU / Location | VRAM | Use |
|--------|---------------|------|-----|
| `*-r7` | R7 RX 7900 XT | 20GB | Big local models (27B), heavy reasoning |
| `*-r5` | R5 RX 6600 | 8GB | Small-model exploration (≤8B), embeddings |
| `*:cloud` / provider | Cloud (OpenRouter) | — | Strongest reasoning, no GPU cost |

This single convention solves two problems at once:
1. **Deterministic routing** — unique names mean each model maps to exactly one backend.
2. **GPU visibility** — the dropdown reads like a map; you always know where inference runs.

To tag R5 models:
```bash
ssh r5 'ollama cp <model> <model>-r5 && ollama rm <model>'
```

### 10. Roles vs. Bases — Zero Lock-In

A role model is a wrapper. Its base LLM is a dropdown you change anytime. You explore freely.

| Role (fixed) | Base LLM (swap freely) | Notes |
|-------------|----------------------|-------|
| orchestrator | deepseek-v4-pro:cloud or qwen3.6:27b-r7 | Needs strongest reasoning for debug chains |
| critic | any :cloud, or explore *-r5 | Occasional use — cheap to run cloud, or test small local |
| archivist | any *-r5 model | Light task — perfect for the 8GB exploration lab |
| researcher | anything | Read-only standalone use |

The exploration workflow:
```bash
1. ssh r5 'ollama pull new-7b && ollama cp new-7b new-7b-r5 && ollama rm new-7b'
2. R7 OWUI dropdown auto-refreshes → "new-7b-r5" appears
3. Pick it as a base for any role, or chat with it directly
4. Watch rocm-smi on R5 to confirm it's running on the 8GB
5. Don't like it? Pick a different -r5 entry. No config, no restart, no lock-in.
```

### 11. The 8GB Reality

R5's RX 6600 holds 8GB. This is a hard physical limit, not a preference.

| Model class | Fits in 8GB? |
|------------|-------------|
| 27B (any quant) | ❌ Never — runs on R7 only |
| 14B @ Q4 | ❌ No room for context |
| 8B @ Q4 | ✅ Yes, decent context |
| 7B @ Q4 | ✅ Comfortable |
| embeddings (bge/nomic) | ✅ Yes |

R5 is your **≤8B exploration lab and embeddings server**. It offloads small models and RAG vectorization from R7 — exactly what 8GB is good for. Never attempt a 27B on R5.

### 12. Cross-Machine Review — Manual First

For Phase 1–5, the **human is the review loop**. The orchestrator proposes; you review; if you want a second opinion, you open the critic in another tab and paste the proposal. Reliable, zero plumbing.

Automated orchestrator→critic API calls are deferred to Phase 6+ polish. Build it only if the manual flow proves too slow.

---

## PART V — THE FOUR MCP SERVERS

### 13. Server Overview

| Server | Purpose | Stack | Risk |
|--------|---------|-------|------|
| r7-filesystem-mcp | Controlled file access | Python 3.12 + MCP SDK | Low |
| github-project-mcp | Repo / issues / PRs / CI | Official GitHub MCP | Low (read), Medium (write) |
| browser-puppeteer-mcp | Headless browser | Node.js + Puppeteer | Low |
| hardware-debug-mcp | JLink / UART / I²C / codec | Python 3.12 + pylink + pyserial | **High — custom build** |

### 14. r7-filesystem-mcp

The model's eyes and hands on R7. Scoped, audited, never exposes secrets.

**Tools:** `fs.list`, `fs.read`, `fs.search`, `fs.stat`, `fs.tree`, `fs.hash`, `fs.diff`, `fs.write` (gated), `fs.patch` (gated), `fs.mkdir` (gated), `fs.trash` (gated)

**Safety:** Read/write only inside profile roots. No `/etc`, no `~/.ssh`, no browser data. Default read-only. Every write logs timestamp, session, path, old/new SHA-256, diff. Destructive ops go to trash, never raw delete.

### 15. github-project-mcp

Correlates code state with hardware findings: issues, branches, PRs, CI, diffs.

**Tools:** `github.issue.list`, `github.issue.get`, `github.pr.list`, `github.pr.diff`, `github.branch.status`, `github.ci.status`, `github.commit.create` (gated), `github.pr.create` (gated), `github.comment` (gated)

**Auth:** `gh auth token` or `GITHUB_TOKEN` env var — never stored in service files.

**Safety:** Only profile-approved repos. Read-only default. Public-facing actions require confirmation.

### 16. browser-puppeteer-mcp

Headless browser for OWUI itself, Jupyter, dashboards, vendor docs, GitHub UI.

**Tools:** `browser.goto` (allowlisted), `browser.screenshot`, `browser.text`, `browser.extract_table`, `browser.wait_for`, `browser.click` (gated), `browser.type` (gated), `browser.download` (gated), `browser.evaluate` (gated), `browser.network_log`

**Safety:** URL allowlist enforced server-side. No stored credentials. Ephemeral profile per session. Screenshots saved to session artifact dir.

### 17. hardware-debug-mcp — The Custom Build

This is the bespoke server. It wraps real hardware tools behind safe named operations. The model never sees raw shell.

**Stack:** Python 3.12, MCP SDK (stdio), pylink-square (SEGGER JLink), pyserial (UART), smbus2 (I²C).

#### 17.1 Session State Machine

```
DISCONNECTED
    │ hw.connect()
    ▼
CONNECTED
    │ hw.identify() → identity matches profile?
    │
    YES │                    NO
    ▼                        ▼
IDENTIFIED              MISMATCH (read-only locked)
    │
    ▼
SAFE_MODE ──────────── default; read-only diagnostics only
    │
    │ hw.enable_debug_mode() [Level 1 confirmation]
    ▼
DEBUG_MODE ─────────── codec config, resets, smoke tests
    │
    │ hw.unlock_dangerous() [Level 2 explicit unlock]
    ▼
DANGEROUS_MODE ─────── flash, program, erase, breakpoints
```

The state machine makes escalation structurally impossible without explicit human approval at each transition.

#### 17.2 Tool Tiers

**Tier 0 — Always Safe (no confirmation):**
`hw.status`, `hw.identify`, `hw.uart.tail`, `hw.rtt.read`, `hw.codec.read_register`, `hw.codec.dump_registers`, `hw.codec.diff_known_good`, `hw.i2c.scan`, `hw.clock.status`, `hw.jtag.detect`, `hw.jlink.read_mem32`, `hw.jlink.read_regs`, `hw.firmware.version`, `hw.state`, `hw.emergency_stop`

**Tier 1 — Confirmation Required:**
`hw.reset.board`, `hw.reset.codec`, `hw.codec.apply_known_good_config`, `hw.uart.send`, `hw.jlink.halt`, `hw.jlink.resume`, `hw.jlink.step`, `hw.run_smoke_test`, `hw.capture_trace`

**Tier 2 — Explicit Unlock + Full Audit:**
`hw.flash_firmware`, `hw.program_fpga`, `hw.jlink.write_mem32`, `hw.jlink.set_breakpoint`, `hw.jlink.write_reg`, `hw.power_cycle`, `hw.erase_flash`

#### 17.3 RTT Is the Primary Debug Channel

Segger RTT (Real-Time Transfer) is non-intrusive — the CPU keeps running while the probe reads a ring buffer via JTAG. No UART pins, no interrupt latency, 100x throughput. Essential for driver development, where UART timing changes behavior. UART is secondary.

#### 17.4 The Tier 2 Confirmation Flow

The server does NOT execute Tier 2 immediately. It returns a pending operation object:

```json
{
  "pending_operation": {
    "id": "op-2026-06-22-103512",
    "tool": "hw.flash_firmware",
    "target": {
      "board_serial": "...",
      "probe_serial": "..."
    },
    "parameters": {
      "image_path": "...",
      "image_hash": "sha256:..."
    },
    "risk": "MEDIUM — overwrites firmware, board resets",
    "expected_result": "New firmware running, UART shows version bump",
    "rollback": "Previous image at build/firmware-prev.elf",
    "expires_in": 120
  }
}
```

You type `confirm op-2026-06-22-103512` or `abort`. Auto-aborted at 120s.

#### 17.5 Hardware Safety Invariants

- **Identity lock** — every Tier 1+ op re-checks board/probe serial against profile; mismatch = refuse.
- **Checkpoint before mutation** — dump registers, record hashes, write checkpoint JSON.
- **Append-only audit** — one JSONL line per hardware call.
- **Emergency stop** — `hw.emergency_stop()` is always Tier 0; halts CPU, disables outputs, drops to SAFE_MODE.
- **Timeouts everywhere.**

---

## PART VI — INFRASTRUCTURE

### 18. The mcpo Bridge

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

**OWUI Tool Server URL:** `http://host.docker.internal:8200` (OWUI runs in Docker; `host.docker.internal` resolves to the R7 host).

mcpo runs as a systemd user service on R7, surviving reboots.

### 19. Safety Architecture (Unified Tier Model)

| Tier | Name | Scope | Confirmation |
|------|------|-------|-------------|
| **0** | Read-only | Always allowed | None |
| **1** | Local writes | Allowed with audit | Model states reason |
| **2** | Controlled mutations | Allowed, logged, confirmed | Human confirms in chat |
| **3** | Dangerous | Explicit confirmation + identity match | Pending operation with expiry |

Audit log format (`/mnt/data-1tb/ai-design-studio/audit/audit.jsonl`):
```json
{"ts":"2026-06-22T19:00:00Z","server":"hardware-debug","tool":"codec.apply_known_good_config","tier":2,"model":"ai-design-orchestrator","session":"debug-2026-06-22-001","args_hash":"abc123","result":"ok","duration_ms":231,"confirmed_by":"human"}
```

### 20. Session Artifacts

Every conversation with the orchestrator produces a self-contained directory that feeds back into the KB:

```
/mnt/data-1tb/ai-design-studio/debug-sessions/
  2026-06-22-1035-codec-output-dead/
    ├── session.json              ← metadata: model, session ID, duration
    ├── conversation.md           ← human-readable transcript
    ├── hardware-audit.jsonl      ← every hardware operation
    ├── register-dumps/           ← timestamped snapshots
    ├── uart-captures/
    ├── rtt-captures/
    ├── screenshots/
    ├── proposed-fixes/           ← diffs the model suggested
    ├── applied-fixes/            ← diffs actually applied
    └── summary.md                ← model-generated debug report
```

### 21. Data Layout

```
/mnt/data-1tb/
├── ollama/models/                    ← Ollama blobs
├── open-webui/                       ← OWUI persistent data
│   ├── webui.db
│   ├── uploads/ vector_db/ cache/
└── ai-design-studio/
    ├── project.profile.json          ← THE KEYSTONE
    ├── env/ads.env                   ← (mode 0600)
    ├── mcp-servers/                  ← wrappers + mcpo config
    │   ├── run-filesystem-mcp.sh
    │   ├── run-github-mcp.sh
    │   ├── run-browser-mcp.sh
    │   ├── run-hardware-mcp.sh
    │   ├── mcpo-config.json
    │   └── start-mcpo.sh
    ├── mcp/hardware-debug/server.py  ← THE CUSTOM SERVER (Phase 3-5)
    ├── mcp-logs/                     ← per-server logs
    ├── audit/audit.jsonl             ← all tool calls
    ├── workspace/                    ← model system prompts, playbooks
    │   ├── ai-design-orchestrator-prompt.txt
    │   ├── ai-design-critic-prompt.txt
    │   ├── ai-design-archivist-prompt.txt
    │   └── ai-design-researcher-prompt.txt
    ├── profiles/                     ← known-good hardware states
    │   └── tdm-8ch-known-good.json
    ├── knowledge/                    ← curated markdown for RAG
    │   ├── register-maps/ datasheets/ playbooks/
    │   ├── openclaw/ openwebui/ ollama/ project-docs/
    ├── debug-sessions/               ← session artifacts (auto)
    ├── browser-captures/             ← screenshots
    ├── artifacts/                    ← traces, reports, bitstreams
    └── .trash/                       ← safe delete target
```

---

## PART VII — EXECUTION

### 22. Build Phases

**Phase 0 — Stabilize Foundation (NOW, ~15 min)**
- Bump OWUI container nofile limit (from 1024 — 896 FDs currently open)
- Regenerate stale OWUI admin JWT token (fresh login)
- Document exact docker run command with all mounts + env
- Confirm Tailscale URL access (:8445)
- Confirm Ollama models + OWUI data on /mnt/data-1tb
- Tag all R5 Ollama models with -r5; optionally tag R7 with -r7

**Phase 1 — Filesystem + GitHub MCP + Orchestrator (Days 1–3)**
- Create /mnt/data-1tb/ai-design-studio/ tree
- Create project.profile.json
- Install + wrap @modelcontextprotocol/server-filesystem
- Install + wrap GitHub MCP server (token from gh auth)
- Install mcpo; create config + systemd user service
- Register mcpo as Tool Server in OWUI (http://host.docker.internal:8200)
- Create ai-design-orchestrator model
- Verify: list project files + GitHub issues end-to-end

**Phase 2 — Browser MCP (Days 4–5)**
- Install Puppeteer/Playwright MCP server
- Wrap with URL allowlist; add to mcpo config
- Verify: screenshot dashboards + extract doc text

**Phase 3 — Hardware MCP, Read-Only (Days 6–10)**
- Build hardware-debug-mcp skeleton + state machine + profile loading + identity check
- Tier 0 tools: status, identify, uart.tail, rtt.read, codec.dump_registers, codec.diff_known_good
- Wire JLink (pylink) + UART (pyserial)
- Build known-good TDM register database
- Verify: hw.codec.diff_known_good() returns correct report

**Phase 4 — Hardware MCP, Controlled Mutations (Days 11–14)**
- Tier 1 tools + confirmation flow
- State transitions (SAFE→DEBUG requires Level 1)
- Checkpoint-before-mutation + audit log
- Verify: full codec register fix session

**Phase 5 — Hardware MCP, Dangerous Tier (Days 15–20)**
- Tier 2 tools + pending-operation protocol
- Smoke test runner + RTT streaming + JTAG breakpoint/step
- Session artifact system
- Verify: firmware flash with full confirmation flow

**Phase 6 — Critic + Archivist + Polish (Days 21–25)**
- Create critic + archivist role models (swappable bases)
- KB curation + RAG collections
- (Optional) Automated orchestrator→critic API calls
- Run 5 real debug scenarios end-to-end
- Write operational runbook

### 23. A Real Session

```
You: Codec output is dead. Check the board.

Orchestrator: Starting diagnostics...

[hw.status] → Probe ✓ Board ✓ UART ✓ Firmware v0.4.2 ✓
[hw.codec.diff_known_good] → 3 registers diverge:
  0x04: live=0x49 expected=0x36 ← INTERFACE MODE
[hw.rtt.read] → "codec_init: wrote mode LJ, expected TDM"

Diagnosis: Codec in Left-Justified, not TDM. Root cause likely
codec_init.c mode constant. This fix is codec register writes only —
no FPGA program, no firmware flash.

Proposing hw.codec.apply_known_good_config()
Risk: LOW. Rollback: state saved to register-dumps/01-initial.json

Proceed?

You: yes

[hw.codec.apply_known_good_config] [hw.codec.diff_known_good] → all match ✓
[hw.run_smoke_test("tdm-loopback")] → PASS ✓

Output is live.

[fs.read drivers/codec_init.c] → line 47 uses CODEC_MODE_LJ

Proposing patch: CODEC_MODE_LJ → CODEC_MODE_TDM. Apply?

You: yes

[fs.patch] → applied, SHA-256 logged.

Want me to open a GitHub issue for this regression, or call the
critic to review before we commit?
```

### 24. OpenClaw Transition

The current OpenClaw codecbot (gateway 18793) is **not deleted** — it becomes a fallback/legacy path:

- **OWUI orchestrator** becomes the primary debug interface
- **OpenClaw codecbot** stays for cron jobs (health checks, state verification), background archiving, and webchat routing
- **OpenClaw GodBot** remains for orchestration, memory, multi-agent routing, and planning work
- Over time, as the OWUI path proves itself, OpenClaw codecbot scales down

---

## PART VIII — DECISIONS LOCKED

| Decision | Answer |
|----------|--------|
| OWUI instances | **One — R7 cockpit.** R5 OWUI optional, unrelated to ADS+MCP. |
| Orchestrator location | **R7 OWUI** — the model you chat with; all 4 MCP tools + write + hardware access |
| Critic / Archivist | **R7 OWUI role models** with swappable bases (cloud or -r5) |
| Model selection | **Fully flexible** — roles fixed, bases swapped from dropdown anytime |
| GPU visibility | **Naming convention:** -r7 / -r5 / :cloud; unique names = deterministic routing |
| R5 8GB role | **≤8B exploration lab + embeddings.** Never a 27B. |
| Cross-machine review | **Manual (human in loop)** for Phase 1–5; automate later if needed |
| MCP bridge | **mcpo**, systemd service on R7, port 8200 |
| Hardware MCP language | **Python 3.12** (pylink-square, pyserial, smbus2) |
| Debug channel | **RTT primary, UART secondary** |
| GitHub formality | **Full — issues, PRs, CI, public-facing quality** |
| KB | **Single collection** on /mnt/data-1tb/.../knowledge/, no cross-OWUI sync needed |
| Data location | **All on /mnt/data-1tb** |
| Project coupling | **None.** Any project plugs in via project.profile.json |

---

## PART IX — THE LAST WORD

ADS+MCP is one cockpit, four scoped tools, and a profile that binds them to a project. Reasoning comes from the cloud or the 20GB card; exploration happens on the 8GB lab; the dropdown is a map that always tells you which GPU you're on. Roles are fixed, brains are swappable, and nothing dangerous happens to your hardware without a named operation, an identity check, and your explicit word.

> The model never touches raw shell.  
> It calls named operations.  
> Named operations have bounded behavior.  
> Bounded behavior can be audited, confirmed, and rolled back.

Build Phase 0. Then Phase 1. The rest follows.

---

*End of ADS+MCP Master Architecture Opus v1.0*
