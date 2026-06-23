# Alchitry Platinum V2 — NeoRV32 Audio System

A RISC-V based audio development platform built on the Alchitry Platinum V2 FPGA board, featuring the [NeoRV32](https://github.com/stnolting/neorv32) soft-core processor, CS42448 multichannel audio codec, and DDR3 memory.

## 🎯 What This Is

This project is the **third generation** of an evolving audio system design:
- **Gen 1:** Early prototypes (pre-GitHub)
- **Gen 2:** Iteration and learning (pre-GitHub)  
- **Gen 3:** This repository — organized, documented, and production-ready

The goal is a self-contained audio development platform with:
- **NeoRV32** RISC-V soft-core @ 100 MHz
- **CS42448** 8-channel audio codec (TDM/I²S)
- **DDR3** 256MB memory via Xilinx MIG
- **Debug console** over UART (v29+)
- **MCP tool integration** for AI-assisted development

## 📁 Repository Structure

```
vivado_neorv32/
├── README.md              # This file
├── LICENSE                # Project license
├── docs/                  # Documentation
│   ├── HARDWARE-DEBUG-RULES.md    # Critical do/don't list
│   ├── PINOUT.md                   # Pin assignments
│   └── MCP-INTEGRATION.md          # AI tool integration
├── firmware/              # NeoRV32 firmware
│   ├── debug_console/     # Interactive debug shell (v29)
│   └── rp2040_uart_passthrough/   # USB UART bridge
├── rtl/                   # Verilog/SystemVerilog sources
│   ├── neorv_basic_plus_top.v    # Top-level design
│   └── ...
├── vivado/                # Vivado project files
│   ├── neorv_basic_plus_top.xpr  # Project
│   └── constraints/
├── agent-workspace/       # Synced from codecbot AI sessions
│   └── ...
└── scripts/               # Automation
    ├── save-to-github.sh           # Formal commit workflow
    ├── flash-firmware.sh           # J-Link programming
    └── test-uart.py                # UART communication test
```

## 🚀 Quick Start

### Prerequisites

- **Alchitry Platinum V2** board with FT2232H USB-UART
- **SEGGER J-Link** or compatible RISC-V debugger
- **Xilinx Vivado** 2023.2+ (for FPGA bitstream)
- **RISC-V GCC** toolchain (for firmware)
- **Python 3.12+** with pyserial

### 1. Flash the Firmware

```bash
cd firmware/debug_console
make clean && make exe
../../scripts/flash-firmware.sh
```

### 2. Connect UART

The board exposes two interfaces via FT2232:
- `/dev/ttyUSB0` — **Primary** (FTDI Channel A, 19200 baud)
- `/dev/ttyACM0` — **Passthrough** (merged with RP2040)

```bash
screen /dev/ttyUSB0 19200
# or
python3 scripts/test-uart.py
```

### 3. Interactive Debug Console

Once connected, the NeoRV32 firmware provides an interactive shell:

```
sys                  — System info (clock, memory sizes)
i2c probe            — Scan I²C bus (finds CS42448 @ 0x4A)
i2c r8 A R           — Read 8-bit register
codec init           — Initialize CS42448 for TDM
clk on|off           — Enable/disable MCLK (GPIO bit 6)
gpio dump            — Show all GPIO states
spi diag             — SPI diagnostic
help                 — Full command list
```

## 🔧 Hardware Architecture

### Clock Tree

| Clock | Frequency | Source |
|-------|-----------|--------|
| CPU (ui_clk) | 100 MHz | MIG DDR3 controller |
| MCLK | 12.288 MHz | clk_wiz_1 MMCM |
| SCLK/LRCLK | Derived | TDM bit clock from MCLK |

### Pin Map (NeoRV32 basic_plus_top)

| Signal | FPGA Pin | Direction | Function |
|--------|----------|-----------|----------|
| UART RX | AA20 | IN | FTDI → NeoRV32 |
| UART TX | AA21 | OUT | NeoRV32 → FTDI |
| I²C SCL | B21 | Bidir | CS42448 clock |
| I²C SDA | E21 | Bidir | CS42448 data |
| GPIO[0] | G2 | OUT | LED (active HIGH) |
| GPIO[1] | E13 | OUT | Codec A0 (address LSB) |
| GPIO[2] | E14 | OUT | Codec A1 (address MSB) |
| GPIO[3] | D14 | OUT | Codec RSTCN (active HIGH) |
| GPIO[6] | — | OUT | CLK_EN (clock enable) |

### Memory Map

| Region | Address | Size | Notes |
|--------|---------|------|-------|
| Boot ROM | 0x00000000 | 128 KB | Shadowed IMEM at boot |
| IMEM (RAM) | 0x80000000 | 128 KB | Instruction memory |
| DMEM (RAM) | 0x80020000 | 128 KB | Data memory |
| DDR3 | 0x20000000 | 256 MB | External DRAM via MIG |
| GPIO | 0xFFFC0000 | — | PORT_IN @ 0x00, PORT_OUT @ 0x04 |

## 🤖 AI Integration (MCP Tools)

This project is designed to work with AI assistants via the **Model Context Protocol (MCP)**:

- **MCP Server**: `hardware-debug-mcp` running on host
- **Tools**: `hw.i2c_scan`, `hw.codec_dump_registers`, `hw.uart_terminal`, etc.
- **Safety**: Tiered access (SAFE → DEBUG → DANGEROUS modes)
- **Audit**: All actions logged to `audit-log.ndjson`

See `docs/MCP-INTEGRATION.md` for setup.

## 📝 Development Workflow

### AI Agent Sessions (codecbot)

Development happens in `~/.openclaw-codecbot/workspaces/codecbot/`, then formally committed:

```bash
# After a productive session:
./scripts/save-to-github.sh "feat: implemented TDM clock validation"

# This:
# 1. Syncs agent workspace → agent-workspace/
# 2. Stages all changes
# 3. Shows diff stats
# 4. Commits with your message
# 5. Pushes to GitHub
```

### Git Commit Discipline

- **Main branch** is always deployable
- **Commit messages** follow conventional commits (`feat:`, `fix:`, `docs:`)
- **Diff is the review** — check `git diff --cached` before commit
- **History is sacred** — never force-push main

## 📜 Version History

| Version | Date | Notes |
|---------|------|-------|
| v29 | 2026-06-19 | Current — Full debug console with codec init |
| v28 | 2026-06-18 | Added SPI display commands |
| ... | ... | See git log |

## 🔗 Related Projects

- [NeoRV32](https://github.com/stnolting/neorv32) — The RISC-V core
- [Alchitry](https://alchitry.com/) — FPGA boards and tutorials
- CS42448 datasheet — Cirrus Logic multichannel codec

## 📄 License

MIT License — See LICENSE file for details.

---

*Built with coffee, J-Link, and an unreasonable amount of UART debugging.*
