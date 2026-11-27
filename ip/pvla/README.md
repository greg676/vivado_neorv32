# PVLA Vivado IP

Catalog IP for the PulseView logic analyzer. Same packaging pattern as the NEORV32 IP already used in this repo (`ipx::package_project` + xgui pages + HDL parameters that resize ports).

**VLNV:** `greg676:user:pvla:1.0`

PHY is the **PR #18/#19** Lucid DATA-before-WR core with **4 KiB write bursts** and `ALWAYS_DRIVE` (`platforms/alchitry-au-v2/rtl/ft601/`). Not the old echo that starved WR. NeoRV32 is not rewritten. This IP does not instantiate MIG.

Pt-only large buffer is a **separate top** (`platforms/alchitry-platinum-v2/rtl/la/pvla_mig7_top.v`): MIG7 256 MB @ `0x20000000` plus the same 4 KiB PHY. Au has no DDR.

## Add to a project

```
Settings → IP → Repository → <repo>/ip
```

Refresh the catalog. Drop **PVLA** on a Block Design. Set **Channels (1–8)**; `probe_i` resizes. Leave **PHY = FT601** for Ft+. Pick **PT_ALPHA**, **PT_V2**, or **AU_V2**.

FT601 pads are I/O of the IP so an IP-scoped XDC can bind package pins (the MIG “pin file” analogue). They are **not** meant to be wired cell-to-cell on the canvas. The example BD TCL — and `bd/bd.tcl` — promote them to the wrapper as `ft_clk`, `ft_data[31:0]`, … matching the XDC names.

Probe ports stay on the canvas for you to wire. Optional **Include Br Bank A probe XDC** is off by default.

## GUI parameters

| Parameter | Default | Effect |
|---|---|---|
| `C_NUM_CH` | 8 | `probe_i[C_NUM_CH-1:0]` |
| `C_SAMPLE_MHZ` | 200 | 100 SDR or 200 DDR @ 100 MHz `ft_clk` |
| `C_PRETRIG_SAMPLES` | 4096 | BRAM depth, power of two. Not DDR3. Live dumps 4 KiB PHY bursts. |
| `C_DEFAULT_POST` | 2048 | Post-trigger samples |
| `C_DEFAULT_SOURCE` | Live | Counter / walking-one / live |
| `C_PHY` | FT601 | STREAM exposes `m_axis_*` |
| `C_BOARD` | PT_ALPHA | PT_ALPHA / PT_V2 / AU_V2 Ft+ XDC |
| `C_HAS_AXI` | Enabled | AXI4-Lite arm/trigger/status |
| `C_INCLUDE_BR_XDC` | No | Optional Br Bank A `probe_i` pins (Pt) |

Counter / walking-one / live all fill two 4 KiB BRAM banks (`la_pingpong_bram`) so the sampler never stalls on TXE. PHY still sees only full 4 KiB write bursts. Pack is four 8-bit samples little-endian per 32-bit word.

## Ports

**Always**

- `probe_i[C_NUM_CH-1:0]` — user-wired
- `status_o[7:0]`

**FT601 (`C_PHY=0`) — auto-promoted, IP XDC, not BD clutter**

- `clk`, `rst_n` — board clock for the PHY reset sequencer
- `ft_clk`, `ft_data[31:0]`, `ft_be[3:0]`, `ft_rxf`, `ft_txe`, `ft_oe`, `ft_rd`, `ft_wr`, `ft_reset`, `ft_wakeup`

**STREAM (`C_PHY=1`)**

- `sample_clk`, `sample_rst_n`
- `m_axis_{tdata,tvalid,tready,tlast,tkeep}`

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
| `hdl/pvla.v` | IP top |
| `hdl/pvla_capture.v` | Packer + dual 4 KiB BRAM ping-pong + PHY mux |
| `../platforms/alchitry-au-v2/rtl/la/la_pingpong_bram.v` | Two 1024×32 banks in front of the PHY |
| `hdl/pvla_axi_lite.v` | AXI4-Lite |
| `xdc/ftplus_ft601_pt_alpha.xdc` | First-batch Ft+ pins |
| `xdc/ftplus_ft601_pt_v2.xdc` | Production Pt Ft+ pins |
| `xdc/ftplus_ft601_au_v2.xdc` | Au V2 Ft+ pins (proven PHY board) |
| `xdc/ftplus_ft601_timing.xdc` | I/O delays (PR #18 0.90 ns output) |
| `xdc/ftplus_ft601_impl.xdc` | IOB packing |
| `xdc/br_bank_a_8ch.xdc` | Optional probe pins |
| `pvla_vivado_ip.tcl` | Packager (run in Vivado to refresh `component.xml`) |
| `xgui/pvla_v1_0.tcl` | GUI |
| `bd/bd.tcl` | Auto-promote FT601 pads |
| `pvla_v1_0_upgrade.tcl` | Old BD still opens |

PHY RTL is referenced from `platforms/alchitry-au-v2/rtl/ft601/` (not copied). This IP does not rewrite NeoRV32.

## Example BD

```bash
# Pt (part xc7a100t) — docs path
cd platforms/alchitry-platinum-v2
vivado -mode batch -source tcl/pvla_bd_example.tcl

# Au (part xc7a35t) — proven PHY, C_BOARD=AU_V2, counter source
cd platforms/alchitry-au-v2
vivado -mode batch -source tcl/pvla_bd_example.tcl
```

Wrapper target name `pvla_bd_wrapper`. Do not program QSPI flash.

## Check (no Vivado)

```bash
python3 ip/pvla/scripts/check_pvla_ip.py
```

## Repackage

```tcl
source ip/pvla/pvla_vivado_ip.tcl
```
