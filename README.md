# LOOM — Multitrack Audio Weaving on FPGA

**A unified AI-assisted hardware development system**

This repository contains three interconnected projects that together form a complete audio development platform:

1. **LOOM** — Multitrack recorder/dubber with software-defined DSP
2. **Alchitry Platinum V2** — Hardware platform (FPGA + FT601 USB3.0)
3. **ADS+MCP** — AI Design Studio with Model Context Protocol tooling

---

## 🎯 What This Is

LOOM is a **standalone hardware multitrack recorder and live source-separation engine** for musicians, built on a single FPGA. No computer. No DAW. You plug in mics and speakers, interact via touchscreen, and the FPGA fabric does real-time multitrack recording, mixing, effects, and — the signature feature — decodes individual instruments out of a stereo room mic onto separate tracks.

### The Three Pillars

```
┌─────────────────────────────────────────────────────────────────┐
│                    LOOM SYSTEM                                  │
├───────────────┬───────────────────┬───────────────────────────┤
│               │                   │                           │
│  LOOM         │  Alchitry Pt V2   │  ADS+MCP                  │
│  Application  │  Hardware Platform│  AI Infrastructure        │
│               │                   │                           │
│  • Multitrack │  • XC7A100T      │  • Open WebUI             │
│    recording  │    FPGA          │  • MCP servers            │
│  • Real-time  │  • CS42448       │  • Hardware debug tools    │
│    DSP        │    8ch codec     │  • GitHub integration      │
│  • Source     │  • DDR3 256MB    │                           │
│    separation │  • FT601 USB3.0  │                           │
│  • Touch UI   │  • NeoRV32 RISC-V│                           │
│               │                   │                           │
└───────────────┴───────────────────┴───────────────────────────┘
```

---

## 📁 Repository Structure

```
loom/
├── README.md                          # This file
├── LICENSE                            # Project license
├── PROJECT-STATUS.md                  # Current build state
│
├── applications/
│   └── loom/                          # The multitrack application
│       ├── docs/
│       │   ├── LOOM_by_opus48.md     # Master architecture doc
│       │   ├── 00-VISION.md          # Product vision
│       │   ├── 01-PRODUCT-SPEC.md    # Specifications
│       │   ├── 02-SYSTEM-ARCH.md     # System architecture
│       │   ├── 03-FPGA-AUDIO.md      # Audio fabric design
│       │   ├── 04-DSP-LIBRARY.md     # DSP modules
│       │   ├── 05-SEPARATOR.md      # Instrument separation
│       │   ├── 06-CONTROL.md         # Control plane
│       │   ├── 07-GUI-DISPLAY.md     # Touchscreen UI
│       │   ├── 08-STORAGE.md         # Recording/storage
│       │   ├── 09-RESOURCES.md       # Resource budget
│       │   ├── 10-STRUCTURE.md       # Project structure
│       │   └── 11-BUILD-PLAN.md      # Implementation plan
│       ├── expanded/                  # AI-expanded design docs
│       ├── rtl/                       # LOOM-specific Verilog
│       └── firmware/                  # LOOM firmware (neorv32)
│
├── platforms/
│   └── alchitry-platinum-v2/          # Hardware platform
│       ├── rtl/                       # NeoRV32 + peripherals
│       ├── constraints/               # XDC pin definitions
│       ├── firmware/                  # Boot firmware
│       │   ├── debug_console/         # Interactive debug shell
│       │   └── rp2040_passthrough/    # USB UART bridge
│       ├── doc/                       # Hardware docs
│       │   ├── HARDWARE-DEBUG-RULES.md
│       │   ├── PINOUT.md
│       │   └── MCP-INTEGRATION.md
│       ├── bd/                        # Vivado block designs
│       ├── neorv32_core/              # NeoRV32 RTL
│       ├── tcl/                       # Build scripts
│       └── scripts/                   # Automation
│           ├── save-to-github.sh      # Formal commit workflow
│           ├── flash-firmware.sh      # J-Link programming
│           └── test-uart.py          # UART test
│
├── infrastructure/
│   └── ads-mcp/                       # AI tooling
│       ├── docs/
│       │   └── ADS+MCP_by_opus48.md   # Master architecture
│       ├── mcp-servers/               # MCP tool implementations
│       │   ├── hardware-debug/        # UART/JTAG debug tools
│       │   ├── r7-filesystem/         # File access
│       │   ├── github-project/        # Git integration
│       │   └── browser-puppeteer/     # Web automation
│       └── profiles/                  # Project profiles
│           └── project.profile.json   # Active configuration
│
└── codebot-workspace/                 # Synced AI sessions
    └── ...                            # From codecbot agent
```

---

## 🚀 Quick Start

### Prerequisites

- **Alchitry Platinum V2** with FT601 add-on board
- **SEGGER J-Link** for RISC-V debugging
- **Xilinx Vivado** 2023.2+ for FPGA synthesis
- **RISC-V GCC** toolchain
- **Python 3.12+** with pyserial

### 1. Connect Hardware

The Alchitry Pt V2 exposes:
- **FT2232H** → `/dev/ttyUSB0` @ 19200 baud (NeoRV32 console)
- **FT601 USB3.0** → High-speed data (future: audio streaming)
- **J-Link** → RISC-V debug and firmware loading

### 2. Flash Boot Firmware

```bash
cd platforms/alchitry-platinum-v2/firmware/debug_console
make clean && make exe
../../scripts/flash-firmware.sh
```

### 3. Connect Debug Console

```bash
screen /dev/ttyUSB0 19200
# or
python3 platforms/alchitry-platinum-v2/scripts/test-uart.py
```

### 4. Interactive Commands

```
sys                  — System info (100 MHz, 128KB IMEM/DMEM)
i2c probe            — Scan I²C (CS42448 @ 0x4A)
codec init           — Initialize codec for TDM
clk on|off           — Enable 12.288 MHz MCLK
gpio dump            — Show GPIO states
help                 — Full command list
```

---

## 🔧 Hardware Architecture

### Alchitry Platinum V2 + FT601 Add-on

| Component | Specification | Notes |
|-----------|---------------|-------|
| FPGA | Xilinx XC7A100T | Artix-7, 100T package |
| Logic Cells | 101,440 | ~15% for LOOM v1 |
| BRAM | 4.86 Mb | Audio buffers, coefficient tables |
| DSP48 | 240 | Time-multiplexed for all channels |
| DDR3 | 256 MB | MIG controller @ 100 MHz |
| Codec | CS42448 | 8ch TDM, I²C control |
| USB 3.0 | FT601 | Future: audio streaming to host |
| Display | 2.4" SPI TFT | 320×240, touch + stylus |
| MCU | NeoRV32 RISC-V | Soft-core @ 100 MHz |

### Clock Tree

| Clock | Frequency | Source | Purpose |
|-------|-----------|--------|---------|
| CPU | 100 MHz | MIG ui_clk | NeoRV32, control plane |
| MCLK | 12.288 MHz | MMCM | Codec master clock |
| SCLK | 3.072 MHz | Derived | TDM bit clock (48k × 64) |
| LRCLK | 48 kHz | Derived | TDM frame sync |

---

## 🤖 AI Integration (ADS+MCP)

The **AI Design Studio** enables natural-language hardware debugging through **Model Context Protocol** tools:

### MCP Servers

| Server | Tools | Purpose |
|--------|-------|---------|
| **hardware-debug** | `hw.i2c_scan`, `hw.codec_dump`, `hw.uart_terminal` | Direct hardware access |
| **r7-filesystem** | `fs.read`, `fs.write`, `fs.tree` | File operations |
| **github-project** | `gh.issues`, `gh.prs`, `gh.commit` | Git integration |
| **browser-puppeteer** | `browser.screenshot`, `browser.navigate` | Web automation |

### Safety Architecture

```
Tier 0 (SAFE)      → Read-only, always allowed
Tier 1 (DEBUG)     → Writes require DEBUG_MODE unlock + confirmation
Tier 2 (DANGEROUS) → Flash writes, requires explicit DANGEROUS_MODE
```

### Example Session

```
User: "Check if the codec is responding"
AI:   hw.i2c_scan() → Finds CS42448 at 0x4A
      hw.codec_dump_registers() → Reads all registers
      
User: "Initialize it for TDM mode"
AI:   hw.enable_debug_mode() → Confirms with user
      hw.codec_apply_known_good() → Applies validated config
```

---

## 📝 Development Workflow

### AI Agent Sessions

Development happens in `~/.openclaw-codecbot/workspaces/codecbot/`, then formally committed:

```bash
# After productive session:
./platforms/alchitry-platinum-v2/scripts/save-to-github.sh \
    "feat: implemented TDM clock validation"

# This:
# 1. Syncs agent workspace → codebot-workspace/
# 2. Stages all changes
# 3. Shows diff stats
# 4. Commits with message
# 5. Pushes to GitHub
```

### Commit Discipline

- **Main branch** always deployable
- **Conventional commits**: `feat:`, `fix:`, `docs:`, `refactor:`
- **Diff is review**: Check `git diff --cached` before commit
- **History immutable**: Never force-push

---

## 📜 Project Status

| Component | Status | Notes |
|-----------|--------|-------|
| Hardware Platform | ✅ Working | NeoRV32 v29, codec responding |
| Debug Console | ✅ Working | UART, I²C, GPIO commands |
| MCP Tools | ⚠️ Partial | Server running, needs parameter fix |
| LOOM Application | 🚧 Design | Architecture complete, RTL pending |
| FT601 Integration | 📋 Planned | USB3.0 audio streaming |
| DSP Engine | 📋 Planned | Time-multiplexed MAC |

---

## 🔗 Documentation

- **LOOM Architecture**: `applications/loom/docs/LOOM_by_opus48.md`
- **ADS+MCP**: `infrastructure/ads-mcp/docs/ADS+MCP_by_opus48.md`
- **Hardware Debug**: `platforms/alchitry-platinum-v2/doc/HARDWARE-DEBUG-RULES.md`

---

## 📄 License

MIT License — See LICENSE file for details.

---

*Built with coffee, J-Link, and an unreasonable amount of UART debugging.*
*Woven on FPGA fabric by AI and human collaboration.*
