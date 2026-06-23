# ADS+MCP — Section 05: HARDWARE DEBUG MCP (The Custom Build)

**Document ID:** ADS-05-HARDWARE-DEBUG-MCP  
**Version:** 1.0  
**Date:** 2026-06-22  
**Author:** GodBot 🜂

---

## 5.1 Overview

This is the bespoke server. It wraps real hardware tools behind safe named operations. The model never sees raw shell.

**Stack:** Python 3.12, MCP SDK (stdio), pylink-square (SEGGER JLink), pyserial (UART), smbus2 (I²C).

---

## 5.2 Session State Machine

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
    │ hw.enable_debug_mode() [Tier 1 confirmation]
    ▼
DEBUG_MODE ─────────── codec config, resets, smoke tests
    │
    │ hw.unlock_dangerous() [Tier 2 explicit unlock]
    ▼
DANGEROUS_MODE ─────── flash, program, erase, breakpoints
```

The state machine makes escalation structurally impossible without explicit human approval at each transition.

---

## 5.3 Tool Tiers

### Tier 0 — Always Safe (no confirmation)

| Tool | Description |
|------|-------------|
| `hw.status()` | Connected probes, board seen, UART alive, firmware version, bitstream hash |
| `hw.identify()` | Full target identification: probe serial, board serial, target CPU |
| `hw.uart.tail(lines)` | Last N lines of UART debug console |
| `hw.uart.stream(duration_ms)` | Capture UART output for duration |
| `hw.rtt.read(channel, lines)` | Read Segger RTT buffer (non-intrusive, no UART pin needed) |
| `hw.rtt.stream(channel, duration_ms)` | Capture RTT burst |
| `hw.codec.read_register(addr)` | Read one codec register |
| `hw.codec.dump_registers()` | Dump all codec registers |
| `hw.codec.diff_known_good()` | Compare live registers to known-good profile |
| `hw.i2c.scan()` | Scan I²C bus, report addresses |
| `hw.clock.status()` | Clock domain status |
| `hw.jtag.detect()` | JTAG chain detection |
| `hw.jlink.read_mem32(addr, count)` | Read memory (CPU halted or running) |
| `hw.jlink.read_regs()` | Read CPU registers |
| `hw.firmware.version()` | Read firmware version string |
| `hw.state()` | Report current session state machine state |
| `hw.emergency_stop()` | **Always available.** Halts CPU, disables outputs, drops to SAFE_MODE. |

### Tier 1 — Confirmation Required

| Tool | Description | Rollback |
|------|-------------|----------|
| `hw.reset.board()` | Hard reset board | None needed |
| `hw.reset.codec()` | Software reset codec | Re-apply known-good config |
| `hw.codec.apply_known_good_config()` | Write known-good register set | Dump before write |
| `hw.uart.send(command)` | Send command over UART | Log response |
| `hw.jlink.halt()` | Halt CPU | Resume |
| `hw.jlink.resume()` | Resume CPU | Halt |
| `hw.jlink.step()` | Single step | Resume |
| `hw.run_smoke_test(test_name)` | Run named hardware smoke test | N/A |
| `hw.capture_trace(duration_ms)` | Capture ETM/ITM trace | N/A |

### Tier 2 — Explicit Unlock + Full Audit

| Tool | Description | Pre-condition |
|------|-------------|---------------|
| `hw.flash_firmware(image_path)` | Flash new firmware | Hash check, board identity match |
| `hw.program_fpga(bitstream_path)` | Program FPGA | Hash check, board identity match |
| `hw.jlink.write_mem32(addr, values)` | Write memory | Must state address range and reason |
| `hw.jlink.set_breakpoint(symbol_or_addr)` | Set breakpoint | Debug mode active |
| `hw.jlink.write_reg(reg, value)` | Write CPU register | Halt required |
| `hw.power_cycle()` | Power cycle target | State known |
| `hw.erase_flash()` | Erase flash | Explicit target + board serial match |

---

## 5.4 RTT Is the Primary Debug Channel

Segger RTT (Real-Time Transfer) is non-intrusive — the CPU keeps running while the probe reads a ring buffer via JTAG. No UART pins, no interrupt latency, 100x throughput. Essential for driver development, where UART timing changes behavior. UART is secondary.

```
hw.rtt.read(channel=0, lines=100)    ← primary debug output
hw.rtt.write(channel=0, data)        ← stimulus injection
hw.rtt.stream(channel=0, duration_ms=5000) ← capture burst
```

---

## 5.5 The Tier 2 Confirmation Flow

The server does NOT execute Tier 2 immediately. It returns a **pending operation object**:

```json
{
  "pending_operation": {
    "id": "op-2026-06-22-103512",
    "tool": "hw.flash_firmware",
    "target": {
      "board": "Arty-Z7-20",
      "board_serial": "SN-XXXX",
      "probe_serial": "XXXXXXXX"
    },
    "parameters": {
      "image_path": "~/projects/active-project/build/firmware.elf",
      "image_hash": "sha256:aabbcc..."
    },
    "risk": "MEDIUM — overwrites firmware, board will reset",
    "expected_result": "New firmware running, UART shows version bump",
    "rollback": "Previous firmware at build/firmware-prev.elf, hash sha256:ddeeff",
    "expires_in": 120
  }
}
```

You type `confirm op-2026-06-22-103512` or `abort`. Auto-aborted at 120 seconds. Expired confirmations are logged.

---

## 5.6 Hardware Safety Invariants

1. **Identity lock** — every Tier 1+ operation re-checks board/probe serial against profile; mismatch = refuse
2. **Checkpoint before mutation** — dump registers, record hashes, write checkpoint JSON before any Tier 1 write
3. **Append-only audit** — one JSONL line per hardware call
4. **Emergency stop** — `hw.emergency_stop()` is always Tier 0; halts CPU, disables outputs, drops to SAFE_MODE
5. **Timeouts everywhere** — no operation blocks indefinitely

---

## 5.7 Server Implementation Skeleton

```python
# hardware-debug-mcp/server.py

import json
import os
from mcp.server import Server, stdio_server
from mcp.types import Tool, TextContent

# Load profile
PROFILE_PATH = os.environ.get(
    "ADS_PROFILE",
    "/mnt/data-1tb/ai-design-studio/project.profile.json"
)
with open(PROFILE_PATH) as f:
    profile = json.load(f)

# State machine
class HardwareState:
    DISCONNECTED = "DISCONNECTED"
    CONNECTED = "CONNECTED"
    IDENTIFIED = "IDENTIFIED"
    MISMATCH = "MISMATCH"
    SAFE_MODE = "SAFE_MODE"
    DEBUG_MODE = "DEBUG_MODE"
    DANGEROUS_MODE = "DANGEROUS_MODE"

state = HardwareState.DISCONNECTED

# Audit log
AUDIT_LOG = profile["audit_log"]

def audit(tool: str, tier: int, result: str, duration_ms: int, confirmed_by: str = None):
    entry = {
        "ts": datetime.utcnow().isoformat() + "Z",
        "server": "hardware-debug",
        "tool": tool,
        "tier": tier,
        "model": os.environ.get("OWUI_MODEL", "unknown"),
        "session": os.environ.get("OWUI_SESSION", "unknown"),
        "result": result,
        "duration_ms": duration_ms,
        "confirmed_by": confirmed_by
    }
    with open(AUDIT_LOG, "a") as f:
        f.write(json.dumps(entry) + "\n")

# Tool implementations
async def hw_status():
    """Tier 0: Report hardware status"""
    # Check probe connection
    # Check board presence
    # Check UART
    # Check firmware version
    # Return status dict
    pass

async def hw_codec_diff_known_good():
    """Tier 0: Compare live registers to known-good"""
    # Read known-good profile
    # Dump live registers
    # Diff
    # Return differences
    pass

# ... (all other tool implementations)

# MCP server setup
server = Server("hardware-debug-mcp")

@server.list_tools()
async def list_tools():
    return [
        Tool(name="hw.status", description="Report hardware status", inputSchema={}),
        Tool(name="hw.identify", description="Full target identification", inputSchema={}),
        # ... all tools
    ]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    # Route to implementation
    # Check tier requirements
    # Check state machine
    # Execute or return pending operation
    pass

if __name__ == "__main__":
    stdio_server.run(server)
```

---

*End of Section 05 — HARDWARE DEBUG MCP*
