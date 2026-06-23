# MCP Integration for Alchitry Pt V2

This document describes how the AI Design Studio (ADS) MCP tools integrate with the NeoRV32 hardware.

## Architecture

```
┌─────────────┐     HTTP      ┌──────────┐     stdio      ┌─────────────┐
│ Open WebUI  │ ─────────────→│  mcpo    │ ──────────────→│ MCP Servers │
│  (owui)     │               │  (:8200) │                │             │
└─────────────┘               └──────────┘                │ • r7-filesystem
                                                          │ • github-project
                                                          │ • browser-puppeteer
                                                          │ • hardware-debug ←──┐
                                                          └─────────────────────┘
                                                                                │
                                                          ┌─────────────────────▼──┐
                                                          │  hardware-debug-mcp    │
                                                          │  (Python server)       │
                                                          └──────────┬─────────────┘
                                                                     │
                                                          ┌──────────▼──────────┐
                                                          │  /dev/ttyUSB0       │
                                                          │  (19200 baud)       │
                                                          └──────────┬──────────┘
                                                                     │
                                                          ┌──────────▼──────────┐
                                                          │  NeoRV32 SoC        │
                                                          │  (debug_console v29)│
                                                          └──────────┬──────────┘
                                                                     │
                                                          ┌──────────▼──────────┐
                                                          │  FPGA Fabric        │
                                                          │  • I²C (CS42448)    │
                                                          │  • SPI (flash/SD)   │
                                                          │  • GPIO (codec ctl) │
                                                          └─────────────────────┘
```

## Tool Reference

### Tier 0 — Read-Only (Always Safe)

| Tool | Description | Example |
|------|-------------|---------|
| `hw.status` | Connection + board info | `curl -X POST .../hw.status -d '{}'` |
| `hw.i2c_scan` | Scan I²C bus | Returns device addresses |
| `hw.codec_dump_registers` | Read all CS42448 regs | 0x00-0x20 |
| `hw.gpio_read` | Read GPIO pin | `hw.gpio_read {"pin": 3}` |
| `hw.uart_terminal` | Send raw command | `hw.uart_terminal {"command": "sys"}` |

### Tier 1 — Write (Requires DEBUG_MODE)

| Tool | Description | Safety |
|------|-------------|--------|
| `hw.enable_debug_mode` | Unlock DEBUG_MODE | Human confirmation |
| `hw.i2c_write` | Write I²C register | Audit logged |
| `hw.codec_apply_known_good` | Restore codec config | Checkpoint first |
| `hw.gpio_write` | Set GPIO output | Immediate effect |
| `hw.system_reset` | Soft reset | Reboots firmware |

### Tier 2 — Dangerous (Requires DANGEROUS_MODE)

| Tool | Description | Risk |
|------|-------------|------|
| `hw.unlock_dangerous` | Unlock DANGEROUS_MODE | Explicit confirm |
| `hw.spi_write` | Write SPI flash | Can corrupt firmware |

## UART Protocol

All commands go through the NeoRV32 debug console:

**Request:**
```
sys\r
```

**Response:**
```
sys
cpu_clk:100000000 IMEM:131072 DMEM:131072
>
```

The firmware echoes the command, then provides output, then `>` prompt.

## Safety Rules

1. **Always read before write** — Dump registers before modifying
2. **Check identity first** — Verify correct board/profile
3. **Use known-good profiles** — `codec apply known-good` is recovery
4. **Emergency stop** — `hw.emergency_stop` always works
5. **Audit everything** — All tier 1+ actions logged to `audit-log.ndjson`

## Setup

```bash
# Start mcpo (MCP-to-OpenAPI bridge)
systemctl --user start mcpo

# Verify tools are accessible
curl -s http://127.0.0.1:8200/hardware-debug/openapi.json | jq '.paths | keys'

# In Open WebUI: Admin → Settings → Tools → Add Tool Server
# URL: http://host.docker.internal:8200
```
