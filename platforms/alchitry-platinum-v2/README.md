# NeoRV32 on Alchitry Pt V2

*A real RISC-V computer. In FPGA fabric. That actually does something.*

[![Wiki](https://img.shields.io/badge/wiki-8_pages-blue)](../../wiki) [![PicoDualProbe](https://img.shields.io/badge/debug_probe-PicoDualProbe-yellow)](https://github.com/greg676/PicoDualProbe) [![MCP Server](https://img.shields.io/badge/AI_tools-15_MCP_tools-green)](https://github.com/greg676/neorv32-mcp)

---

Most FPGA soft-core tutorials end at `printf("hello world")` on a UART. This one doesn't.

This is a **100 MHz RISC-V system-on-chip** with 256 MB of DDR3, an 8-channel audio codec, a color touchscreen, SPI flash storage, and a JTAG debug interface — all running on an Alchitry Platinum V2. The firmware is a debug console that can interrogate every peripheral on the board. Two MCP servers give AI agents safe, structured access to the hardware.

```
XC7A100T Artix-7 FPGA
├── NeoRV32 RV32I @ 100 MHz
├── 256 MB DDR3 (MIG)
├── CS42448 6-in/8-out audio codec (I²C)
├── ILI9341 320×240 TFT (SPI)
├── XPT2046 touch (SPI)
├── W25Q64 64 Mbit flash (SPI)
└── JTAG debug (PicoDualProbe or J-Link)
```

## What Makes This Different

- **Real peripherals, not blinky LEDs.** I²C codec config, SPI bus with 4 devices, DDR3 memory controller, JTAG debug transport module.
- **Real firmware.** A debug console with `sys`, `id`, `i2c scan`, `codec status`, `spi status` commands — you can interrogate the hardware from a terminal.
- **Real tooling.** 15 MCP tools let AI agents safely control the board — halt the CPU, read registers, flash firmware, recover from bad flashes.
- **Real documentation.** The [wiki](../../wiki) covers every subsystem, every gotcha, every build step. No guessing.

## Quick Start

```bash
# 1. Build the bitstream
cd platform && vivado -mode batch -source build.tcl

# 2. Build firmware
cd ../firmware && ./build.sh

# 3. Load bitstream via Alchitry Loader
# 4. Connect terminal: screen /dev/ttyUSB0 19200
# 5. You should see:
CMD:> h
Available CMDs:
h: Help    i: System info    r: Restart
u: Upload  l: SPI flash load  s: SPI flash program
e: Execute x: Exit
```

## Resource Usage

| Resource | Used | Available | % |
|----------|------|-----------|----|
| LUTs | 9,152 | 63,400 | 14% |
| Registers | 8,173 | 126,800 | 6% |

**86% of the FPGA is still free.** Room for DSP engines, a second CPU core, hardware accelerators.

## Hardware Reference

| What | Detail |
|------|--------|
| **FPGA** | XC7A100T-2FGG484 (Artix-7) |
| **CPU** | NeoRV32 RISC-V (RV32I + Zicsr + Zifencei) @ 100 MHz |
| **Memory** | 128 KB IMEM + 128 KB DMEM + 256 MB DDR3 |
| **Audio** | CS42448 6-in/8-out TDM codec (I²C @ 0x48) |
| **Display** | ILI9341 2.4" 320×240 TFT (SPI) |
| **Touch** | XPT2046 resistive (SPI) |
| **Storage** | W25Q64 64 Mbit SPI flash |
| **Debug** | JTAG via PicoDualProbe or J-Link |
| **Console** | UART 19200 baud via FTDI |

## JTAG Debug

```bash
# PicoDualProbe (recommended):
openocd -f scripts/openocd/picodualprobe-jtag.cfg -f scripts/openocd/neorv32.cfg

# J-Link (legacy):
JLinkExe -device RISC-V -if JTAG -speed 1000 -autoconnect 1
```

| Property | Value |
|----------|-------|
| IR length | 5 bits |
| IDCODE | 0x00000001 |
| DTMCS | 0x00000071 |

## Gotchas

1. **UART baud is 19200, NOT 115200** — the profile was wrong
2. **Flash is W25Q64, NOT MX25L6406E** — the profile was wrong
3. **J-Link: 1 MHz only, wait 3-5s** between sessions
4. **Use `elf.bin`, NOT `neorv32_exe.bin`** — the 8-byte header crashes the CPU
5. **CS42448 reg 0x04 = 0x36 for TDM** — 0x49 is Left-Justified (cost weeks)
6. **Clear PDN (reg 0x02) LAST** — after all other codec registers
7. **SPI bus arbiter mandatory** — 4 devices on shared bus
8. **`neorv32_uart0_char_received()` doesn't read the byte** — use `_get()`
9. **`neorv32_uart0_printf` doesn't support `%02x`** — use `phex()`
10. **GPIO `pin_get()` reads PORT_IN, not PORT_OUT**
11. **Do NOT unbind the FTDI USB interface** — crashes the FPGA
12. **Wait 3-5 seconds between J-Link sessions** — TAP needs recovery time

Full details: [Wiki → Gotchas](../../wiki/Gotchas)

## Companion Projects

| Project | What |
|---------|------|
| **[PicoDualProbe](https://github.com/greg676/PicoDualProbe)** | $5 dual SWD/JTAG debug probe |
| **[NeoRV32 MCP Server](https://github.com/greg676/neorv32-mcp)** | AI agent bridge — 15 tools for hardware control |

## Status

**Active.** Bitstream v0.29, firmware debug-console rev0. MCP server v3 tested against live hardware.

MIT License
