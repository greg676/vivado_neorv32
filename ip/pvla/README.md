# PVLA Vivado IP

Catalog IP for the PulseView logic analyzer. Same packaging pattern as the NEORV32 IP already used in this repo (`ipx::package_project` + xgui pages + HDL parameters that resize ports).

**VLNV:** `greg676:user:pvla:1.0`

## Add to a project

```
Settings → IP → Repository → <repo>/ip
```

Refresh the catalog. Drop **PVLA** on a Block Design. Set **Channels (1–8)**; `probe_i` resizes. Leave **PHY = FT601** for Ft+. Pick **PT_ALPHA** (first-batch DATA[0:13]) or **PT_V2** (production).

FT601 pads are I/O of the IP so an IP-scoped XDC can bind package pins (the MIG “pin file” analogue). They are **not** meant to be wired cell-to-cell on the canvas. The example BD TCL — and `bd/bd.tcl` — promote them to the wrapper as `ft_clk`, `ft_data[31:0]`, … matching the XDC names.

Probe ports stay on the canvas for you to wire. Optional **Include Br Bank A probe XDC** is off by default.

## GUI parameters

| Parameter | Default | Effect |
|---|---|---|
| `C_NUM_CH` | 8 | `probe_i[C_NUM_CH-1:0]` |
| `C_SAMPLE_MHZ` | 200 | 100 SDR or 200 DDR @ 100 MHz `ft_clk` |
| `C_PRETRIG_SAMPLES` | 4096 | BRAM depth, power of two. Not DDR3. |
| `C_DEFAULT_POST` | 2048 | Post-trigger samples |
| `C_DEFAULT_SOURCE` | Live | Counter / walking-one / live |
| `C_PHY` | FT601 | STREAM exposes `m_axis_*` |
| `C_BOARD` | PT_ALPHA | Selects which Ft+ XDC is included |
| `C_HAS_AXI` | Enabled | AXI4-Lite arm/trigger/status |
| `C_INCLUDE_BR_XDC` | No | Optional Br Bank A `probe_i` pins |

## Ports

**Always**

- `probe_i[C_NUM_CH-1:0]` — user-wired
- `status_o[7:0]`

**FT601 (`C_PHY=0`) — auto-promoted, IP XDC, not BD clutter**

- `clk`, `rst_n` — board clock and Pt button (`ft_reset = rst_n` after 2 flops; no post-DONE RESET_N pulse)
- `ft_clk`, `ft_data[31:0]`, `ft_be[3:0]`, `ft_rxf`, `ft_txe`, `ft_oe`, `ft_rd`, `ft_wr`, `ft_reset`, `ft_wakeup`

**STREAM (`C_PHY=1`)**

- `sample_clk`, `sample_rst_n`
- `m_axis_{tdata,tvalid,tready,tlast,tkeep}`

**AXI (`C_HAS_AXI=1`)** — `s_axi_*` (32-bit, addr 8-bit)

| Offset | Name | |
|---|---|---|
| 0x00 | CMD | Same 32-bit word as the FT601 host path |
| 0x04 | STATUS | armed / triggered / done / overflow / source |
| 0x08 | OVERFLOW | |
| 0x0C | DROP | |
| 0x10 | IDENT | `32'h414C5650` `"PVLA"` |

## Files

| Path | Role |
|---|---|
| `hdl/pvla.v` | IP top |
| `hdl/pvla_capture.v` | Wrapper around existing LA RTL + PHY mux |
| `hdl/pvla_axi_lite.v` | AXI4-Lite |
| `xdc/ftplus_ft601_pt_alpha.xdc` | First-batch Ft+ pins |
| `xdc/ftplus_ft601_pt_v2.xdc` | Production Ft+ pins |
| `xdc/ftplus_ft601_timing.xdc` | I/O delays (PR #5 numbers) |
| `xdc/ftplus_ft601_impl.xdc` | IOB packing |
| `xdc/br_bank_a_8ch.xdc` | Optional probe pins |
| `pvla_vivado_ip.tcl` | Packager (run in Vivado to refresh `component.xml`) |
| `xgui/pvla_v1_0.tcl` | GUI |
| `bd/bd.tcl` | Auto-promote FT601 pads |
| `pvla_v1_0_upgrade.tcl` | Old BD still opens |

Existing capture RTL is referenced from `platforms/alchitry-platinum-v2/rtl/{la,ft601}/`. This IP does not rewrite NeoRV32.

## Example BD

```bash
cd platforms/alchitry-platinum-v2
vivado -mode batch -source tcl/pvla_bd_example.tcl
# set pvla_num_ch 4; set pvla_board 1;  before sourcing if needed
```

Do not program QSPI flash. RAM program is `tcl/program_ram.tcl` when a bitstream exists.

## Repackage

```tcl
source ip/pvla/pvla_vivado_ip.tcl
```
