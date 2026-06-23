# ADS+MCP — Section 06: SAFETY ARCHITECTURE

**Document ID:** ADS-06-SAFETY-ARCHITECTURE  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 6.1 Unified Tier Model

All four MCP servers share a unified safety tier system:

| Tier | Name | Scope | Confirmation |
|------|------|-------|-------------|
| **0** | Read-only | Always allowed | None |
| **1** | Local writes | Allowed with audit | Model states reason |
| **2** | Controlled mutations | Allowed, logged, confirmed | Human confirms in chat |
| **3** | Dangerous | Explicit confirmation + identity match | Pending operation with expiry |

### Tier 0 — Read-only always allowed
- File reads, github reads, browser screenshots
- Hardware status, register dumps, I²C scans, JTAG reads

### Tier 1 — Local writes allowed with audit
- File writes (within write roots), debug session reports
- Model must state reason; operation is logged

### Tier 2 — Controlled mutations
- Codec register writes, board resets, smoke tests
- Human confirms in chat; operation is logged with full detail

### Tier 3 — Dangerous
- Firmware flash, FPGA program, JTAG breakpoints/memory writes
- Power cycle, flash erase
- GitHub public writes (PRs, comments)
- Pending operation protocol with expiry; identity match required

---

## 6.2 Audit Log

**Location:** `/mnt/data-1tb/ai-design-studio/audit/audit.jsonl`

**Format (one JSON object per line):**

```json
{
  "ts": "2026-06-22T19:00:00Z",
  "server": "hardware-debug",
  "tool": "codec.apply_known_good_config",
  "tier": 2,
  "model": "ai-design-orchestrator",
  "session": "debug-2026-06-22-001",
  "args_hash": "abc123",
  "result": "ok",
  "duration_ms": 231,
  "confirmed_by": "human"
}
```

**Properties:**
- Append-only — never modified after write
- One line per tool call
- Queryable with `jq` for analysis
- Rotated monthly to `audit-YYYY-MM.jsonl`

---

## 6.3 Identity Lock

Every Tier 1+ hardware operation re-checks:

1. **Board serial** — matches `project.profile.json` hardware.board_serial
2. **Probe serial** — matches `project.profile.json` hardware.probe.serial
3. **Target device** — matches expected target

If any check fails, the operation is refused and logged as `"result": "identity_mismatch"`.

---

## 6.4 Checkpoint Before Mutation

Before any Tier 1+ hardware write, the server:

1. Dumps current register state to session artifact dir
2. Records current firmware hash
3. Records current bitstream hash
4. Writes checkpoint JSON: `register-dumps/<timestamp>-pre-mutation.json`

This enables rollback and post-mortem analysis.

---

## 6.5 Emergency Stop

`hw.emergency_stop()` is **always Tier 0** — no confirmation required, available in any state.

Actions:
1. Halt CPU (if running)
2. Disable outputs (if applicable)
3. Drop session to SAFE_MODE
4. Log emergency stop event

---

## 6.6 Timeouts

| Operation | Timeout | On Timeout |
|-----------|---------|------------|
| UART read | 5s | Return partial data |
| RTT read | 5s | Return partial data |
| JTAG connect | 10s | Return error |
| Codec I²C | 2s | Return error, retry once |
| Flash write | 60s | Return error, verify state |
| FPGA program | 30s | Return error, verify state |
| Pending operation | 120s | Auto-abort, log expiry |

---

## 6.7 Safety Rules Summary

1. **Default deny** — everything is read-only unless explicitly allowed
2. **Identity before action** — verify target before any mutation
3. **Checkpoint before write** — save state before changing it
4. **Audit everything** — every tool call is logged
5. **Emergency stop always available** — no confirmation, no state restriction
6. **Timeouts on everything** — no operation blocks indefinitely
7. **No raw shell** — the model calls named operations, never arbitrary commands

---

*End of Section 06 — SAFETY ARCHITECTURE*
