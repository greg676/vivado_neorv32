# vivado_neorv32 — Alchitry Pt V2 NeoRV32 FPGA Project

RISC-V soft-core processor on the Alchitry Platinum V2 (XC7A100T) with CS42448 audio codec and FT601 USB 3.0 FIFO interface.

## Hardware Platform

| Component | Part | Notes |
|-----------|------|-------|
| Board | Alchitry Pt V2 | XC7A100T-2FGG484I |
| Add-ons | Ft+ (FT601Q) + Br breakout | USB 3.0 + I/O breakout |
| Debug | Segger J-Link EDU Mini V2 | JTAG to NeoRV32 OCD |
| UART Bridge | RP2040 Zero (GP0/GP1) | CircuitPython USB-UART passthrough |
| Audio Codec | CS42448 | I²C addr 0x48, TDM audio |
| Clock Gen | Si5351A | I²C addr 0x60, 25MHz XTAL |

## Project Structure

```
vivado_neorv32/
├── bd/                  # Vivado block designs (.bd)
│   ├── neorv_basic.bd         # Minimal: CPU + clocking
│   ├── neorv_basic_plus.bd    # Basic + GPIO + TWI + SPI
│   ├── neorv_noddr.bd         # No DDR, codec interface
│   ├── neorv_ddr.bd           # DDR + AXI interconnect
│   └── neorv_ddr_codec.bd     # Full: DDR + codec + FT601
├── constraints/         # XDC pin constraints
│   ├── ptv2_basic.xdc         # Minimal pinout
│   ├── ptv2_basic_plus.xdc    # Extended pinout
│   ├── ptv2_codec.xdc         # Codec I/O
│   └── neorv_noddr_top.xdc    # No-DDR pinout
├── rtl/                 # Top-level Verilog wrappers
│   ├── neorv_basic_top.v
│   ├── neorv_basic_plus_top.v
│   ├── neorv_noddr_top.v
│   ├── neorv_ddr_top.v
│   └── neorv_ddr_codec_top.v
├── firmware/            # NeoRV32 application firmware
│   ├── hello_uart/           # UART echo test (working)
│   ├── hello_cpu/            # CPU diagnostics
│   └── lib/                  # Shared library code
├── neorv32_core/        # NeoRV32 RISC-V processor (VHDL)
├── tcl/                 # Vivado TCL build scripts
└── doc/                 # Project documentation
```

## NeoRV32 Core

**Source:** [github.com/stnolting/neorv32](https://github.com/stnolting/neorv32) (nightly development tree)

The core VHDL sources (121 files in `rtl/core/`) are NOT tracked in this repo. They live in:
- **Local reference:** `~/vivado_projects/neorv32-main/rtl/`
- **Upstream:** Add as a git submodule when tracking a specific release

## Block Designs

### neorv_basic — Minimal Boot Design ✅ WORKING
- 1x clk_wiz (100 MHz → 160 MHz)
- 1x NeoRV32 CPU (RV32IM + Zicond, 128 KB IMEM/DMEM)
- UART0 via RP2040 bridge
- JTAG debug via J-Link
- **Bitstream built and tested:** `hello_uart` echoes end-to-end

### neorv_basic_plus — Peripheral I/O
- Adds GPIO, TWI (I²C), SPI
- For CS42448 + Si5351A communication

### neorv_noddr — Audio Codec Interface
- Codec I²C + I²S/TDM without DDR
- MCLK generation via second MMCM

### neorv_ddr — DDR Memory
- MIG 7-series + AXI SmartConnect
- Larger firmware / data space

### neorv_ddr_codec — Full System
- DDR + codec + FT601 USB 3.0
- Target architecture for audio streaming

## Key Pins

| Signal | Pin | Function |
|--------|-----|----------|
| CLK100M | W19 | Board oscillator input |
| UART0 TX | B15 | FPGA → RP2040 |
| UART0 RX | F19 | RP2040 → FPGA |
| TWI SCL | B20 | I²C clock → codec/clock gen |
| TWI SDA | C14 | I²C data |
| CODEC RST | D14 | GPIO out[2] |
| MCLK | D16 | 12.288 MHz audio clock |
| JTAG TCK | L16 | J-Link |
| JTAG TMS | J18 | J-Link |
| JTAG TDI | K18 | J-Link |
| JTAG TDO | G14 | → J-Link |

## Clock Configuration

| Source | Frequency | MMCM | Output |
|--------|-----------|------|--------|
| Board OSC (W19) | 100 MHz | — | System input |
| clk_wiz_0 | 100 MHz → 160 MHz | 10×/6.25 | CPU core clock |
| clk_wiz_1 | 100 MHz → 12.288 MHz | — | Audio MCLK (codec) |

⚠️ **Clock mismatch known issue:** `CLOCK_FREQUENCY` generic currently 100 MHz, actual CPU clock 160 MHz. Fix by updating the NeoRV32 IP parameter.

## Firmware Build

```bash
cd firmware/hello_uart
make NEORV32_HOME=~/vivado_projects/neorv32-main clean_all exe
```

## Flash via J-Link

```bash
JLinkExe -device RISC-V -if JTAG -speed 4000 -autoconnect 1 \
  -JTAGConf "-1,-1" -CommanderScript firmware/hello_uart/flash.jlink
```

## Vivado Project

The working Vivado project is at:
```
~/vivado_projects/alchirty_ptv2/pt_tf_neorv32/
```

To regenerate from this repo:
1. Create a new Vivado project targeting XC7A100T-2FGG484I
2. Add sources from `rtl/`, constraints from `constraints/`
3. Import block designs from `bd/`
4. Point NeoRV32 IP to `neorv32_core/`
5. Generate bitstream

## Git Workflow

- **Main branch:** Working designs
- **Feature branches:** Per-block-design changes
- **Tags:** Stable bitstream checkpoints

## Status: June 2026

✅ JTAG connected, CPU detected, firmware loads
✅ UART0 echo working end-to-end
✅ Bitstream builds from `neorv_basic` BD
🔧 MCLK generation (clk_wiz_1) — in progress
🔧 I²C codec communication — needs MCLK
🔧 Clock frequency generic mismatch
⭕ DDR migration — not started
⭕ FT601 USB 3.0 — not started
