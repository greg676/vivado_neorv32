# PVLA Vivado IP

Catalog IP for the PulseView logic analyzer. Same packaging pattern as the NEORV32 IP already used in this repo (`ipx::package_project` + xgui pages + HDL generics that resize ports).

**VLNV:** `greg676:user:pvla:1.0`

Educational **4 / 8 / 16-channel packer**: N samples fill one 32-bit USB word. First board is **Alchitry Au V2 + Ft+ FT601**. PHY is the PR #18/#19 Lucid DATA-before-WR core with **4 KiB write bursts**. Default pads are **IOBUF 245** (real 32-bit inout, TX-only protocol, RX unused). `ALWAYS_DRIVE` is an escape hatch. NeoRV32 is not rewritten. No MIG. No QSPI.

## Add to a project

```
Settings → IP → Repository → <repo>/ip
```

Refresh the catalog. Drop **PVLA** on a Block Design. Default config streams an internal counter (8 ch, Au pinout) without wiring. Route the signal under study into `probe_i` (internal BD probe) or switch the path to external LVCMOS33 pins.

FT601 pads are I/O of the IP so an IP-scoped XDC can bind package pins (the MIG “pin file” analogue). They are **not** meant to be wired cell-to-cell on the canvas.

## Packing (32-bit USB word, `BE=0xF`)

| `C_NUM_CH` | Samples / word | Layout (oldest → newest) |
|---|---|---|
| 4 | 8 | `[3:0]=t+0` … `[31:28]=t+7` |
| **8** (default) | 4 | `[7:0]=t+0` … `[31:24]=t+3` |
| 16 | 2 | `[15:0]=t+0` … `[31:16]=t+1` |

RTL: `hdl/pvla_word_packer.v` (generate mux/shift, not hidden in the PHY).

## GUI parameters

| Parameter | Default | Effect |
|---|---|---|
| `C_NUM_CH` | **8** | 4 / 8 / 16 packing mode; resizes `probe_i` |
| `C_INPUT_PATH` | Internal | Internal fabric **or** external pins (not mixed) |
| `C_DEFAULT_SOURCE` | Counter | Counter / walking-one / BD `probe_i` (internal path only) |
| `C_SAMPLE_CLK_SRC` | FT601 100 MHz | `ft_clk` or external `sample_clk` |
| `C_SAMPLE_MHZ` | 100 | Frequency of that clock (FT601 is 100) |
| `C_SAMPLE_DIV` | 1 | 1 / 2 / 4 / 8. Sample rate = MHz / div |
| `C_PAD_MODE` | IOBUF 245 | IOBUF (default) or ALWAYS_DRIVE |
| `C_PHY` | FT601 | STREAM exposes `m_axis_*` |
| `C_BOARD` | **AU_V2** | PT_ALPHA / PT_V2 / AU_V2 Ft+ XDC |
| `C_HAS_AXI` | Off | AXI4-Lite arm/trigger/status |
| `C_PRETRIG_SAMPLES` | 4096 | BRAM depth, power of two. Not DDR3. |
| `C_INCLUDE_BR_XDC` | No | Optional Br Bank A `probe_i` pins (Pt) |

Rate math: `usb_Mword/s = (C_SAMPLE_MHZ / C_SAMPLE_DIV) / (32 / C_NUM_CH)`. Must be ≤ 100 (FT601 `ft_clk`). Example: 8 ch @ 100 MS/s → **25 Mword/s** USB.

## Ports

**Always**

- `probe_i[C_NUM_CH-1:0]` — BD fabric or external pins
- `status_o[7:0]`

**FT601 (`C_PHY=0`) — auto-promoted, IP XDC, not BD clutter**

- `clk`, `rst_n` — board clock for the PHY reset sequencer
- `ft_clk`, `ft_data[31:0]`, `ft_be[3:0]`, `ft_rxf`, `ft_txe`, `ft_oe`, `ft_rd`, `ft_wr`, `ft_reset`, `ft_wakeup`

**Sample clock (`C_SAMPLE_CLK_SRC=1` or STREAM)**

- `sample_clk`, `sample_rst_n`

**STREAM (`C_PHY=1`)** — `m_axis_{tdata,tvalid,tready,tlast,tkeep}`

**AXI (`C_HAS_AXI=1`)** — `s_axi_*` (32-bit, addr 8-bit)

| Offset | Name | |
|---|---|---|
| 0x00 | CMD | `[1:0]` source, `[2]` arm, `[3]` soft trigger, `[4]` abort |
| 0x04 | STATUS | armed / triggered / done / overflow / source |
| 0x08 | OVERFLOW | |
| 0x0C | DROP | |
| 0x10 | IDENT | `32'h414C5650` `"PVLA"` |

## Files

| Path | Role |
|---|---|
| `hdl/pvla_word_packer.v` | Visible 4/8/16 → 32-bit USB word |
| `hdl/pvla_internal_src.v` | Counter / walking-one / probe mux |
| `hdl/pvla.v` | IP top |
| `hdl/pvla_capture.v` | Packer + 4 KiB ping-pong + PHY |
| `hdl/pvla_axi_lite.v` | AXI4-Lite |
| `xdc/ftplus_ft601_*.xdc` | Ft+ pins / timing / IOB |
| `pvla_vivado_ip.tcl` | Packager |
| `xgui/pvla_v1_0.tcl` | GUI |
| `scripts/tb_pvla_word_packer.py` | Golden pack (no Vivado) |
| `scripts/check_pvla_ip.py` | Structural check |

PHY RTL is referenced from `platforms/alchitry-au-v2/rtl/ft601/` (not copied). This IP does not rewrite NeoRV32.

## Example BD

```bash
# Au (part xc7a35t) — default, proven PHY, C_BOARD=AU_V2, internal counter
cd platforms/alchitry-au-v2
vivado -mode batch -source tcl/pvla_bd_example.tcl

# Pt (part xc7a100t)
cd platforms/alchitry-platinum-v2
vivado -mode batch -source tcl/pvla_bd_example.tcl
```

Wrapper target name `pvla_bd_wrapper`. Do not program QSPI flash.

## Check (no Vivado)

```bash
python3 ip/pvla/scripts/tb_pvla_word_packer.py
python3 ip/pvla/scripts/check_pvla_ip.py
```

## Repackage

```tcl
source ip/pvla/pvla_vivado_ip.tcl
```
