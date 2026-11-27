# PVLA — fabric logic analyzer over FT601

**Repo:** [https://github.com/greg676/vivado_neorv32](https://github.com/greg676/vivado_neorv32)

Vivado IP that samples 1–8 LVCMOS33 probes in the FPGA and streams them to **PulseView** (libsigrok). First PHY is the Alchitry **Ft+** FT601 SuperSpeed FIFO. This is not AMD ILA / Vivado Hardware Manager.

Working RTL lives in open PRs **#16–#25** (there is no #21). `main` still has the older NeoRV32 / LOOM tree.

## Status (Au, live)

Alchitry **Au** `xc7a35t` + Ft+ V2 on **jetson-edge**. SRAM reload only. **No QSPI.** SuperSpeed `0403:601f` @ 5000M. Overlapped D3XX IN.

| Path | Rate | vs 381.47 MiB/s theoretical |
|---|---:|---:|
| Capture IN **sink** ([#24](https://github.com/greg676/vivado_neorv32/pull/24)) | **335 MiB/s** | 88% |
| Capture IN **verified** packed counter | **257 MiB/s** | 67% (`words_ok` consecutive, 0 bad) |
| TX-only sink (USB ceiling, [#23](https://github.com/greg676/vivado_neorv32/pull/23)) | 335 MiB/s | 88% |

32-bit × 100 MHz `ft_clk` = 400 MB/s = **381.47 MiB/s**. Remaining verify-vs-sink gap is Jetson memcpy, not the FPGA packer.

![PulseView 0.4.2: 8-bit packed counter from Au SRAM capture (D0 fastest … D7 slowest)](media/pulseview-counter.png)

PulseView **0.4.2** / sigrok-cli **0.7.2** open the host `.sr` ([#19](https://github.com/greg676/vivado_neorv32/pull/19)). Simulated LAT3 → `.sr` is [#6](https://github.com/greg676/vivado_neorv32/pull/6).

## Hardware sandwich (stock)

```
Ft+ FT601Q  → USB 3 host
        │  top connector
FPGA (Au xc7a35t  or  Pt V2 XC7A100T + DDR3)
        │  bottom connector
Br (or later LA input board)
```

Ft+ stays on top. Bottom is the instrument. **SRAM / RAM bitstream only** — never `--write-flash`, `.mcs`, or QSPI.

## Where to start

| You want | Open |
|---|---|
| Proven Au PHY + 335 MiB/s capture | [#24](https://github.com/greg676/vivado_neorv32/pull/24) · tree [`platforms/alchitry-au-v2/`](https://github.com/greg676/vivado_neorv32/blob/cursor/au-packer-fwft-f2d0/platforms/alchitry-au-v2/README.md) |
| PulseView `.sr` from live IN | [#19](https://github.com/greg676/vivado_neorv32/pull/19) |
| PVLA catalog IP (`greg676:user:pvla:1.0`) | [#20](https://github.com/greg676/vivado_neorv32/pull/20) · [`ip/pvla/`](https://github.com/greg676/vivado_neorv32/blob/cursor/pvla-bd-ip-a9a6/ip/pvla/README.md) |
| Pt 256 MB DDR3 capture buffer | **[#25](https://github.com/greg676/vivado_neorv32/pull/25)** · `pvla_mig7_top` (Pt only; Au has no DDR) |
| NeoRV32 SoC (unchanged) | [`platforms/alchitry-platinum-v2/README.md`](platforms/alchitry-platinum-v2/README.md) |

Checkout the Au packer branch for the working instrument:

```bash
git clone https://github.com/greg676/vivado_neorv32.git
cd vivado_neorv32
git checkout cursor/au-packer-fwft-f2d0   # PR #24
```

SRAM load (Au). Confirm `idcode` `0x362d093` / xc7a35 **every** reload:

```bash
openFPGALoader --fpga-part xc7a35tftg256 --write-sram \
    platforms/alchitry-au-v2/bitstreams/la_capture_top_v2.bit
# then overlapped D3XX IN, or write a PulseView .sr:
# python3 platforms/alchitry-au-v2/host/ft601-capture/ft601_capture.py \
#     --backend d3xx --bytes 16384 --chunk-bytes 4096 --sr /tmp/au-la.sr
# pulseview -c -D -i /tmp/au-la.sr
```

Do **not** load a Pt `xc7a100t` bitstream onto Au.

## PRs 16–25

Au stack (SRAM, no NeoRV32, no QSPI):

| PR | What |
|---|---|
| [#16](https://github.com/greg676/vivado_neorv32/pull/16) | Au V2 + Ft+ 245 loopback (`xc7a35t`, SRAM) |
| [#17](https://github.com/greg676/vivado_neorv32/pull/17) | TX-only vs RX-only isolation |
| [#18](https://github.com/greg676/vivado_neorv32/pull/18) | Lucid WR / DATA IOB phasing (working PHY) |
| [#19](https://github.com/greg676/vivado_neorv32/pull/19) | 4 KiB TX bursts → PulseView `.sr` |
| [#20](https://github.com/greg676/vivado_neorv32/pull/20) | PVLA Vivado BD IP on that PHY |
| [#22](https://github.com/greg676/vivado_neorv32/pull/22) | Dual 4 KiB BRAM in front of the PHY |
| [#23](https://github.com/greg676/vivado_neorv32/pull/23) | Overlapped D3XX IN (256 KiB–1 MiB URBs) |
| [#24](https://github.com/greg676/vivado_neorv32/pull/24) | FIFO36 FWFT packer — capture IN **335 MiB/s** |

Platinum DDR3 (separate top, still no CPU rewrite):

| PR | What |
|---|---|
| **[#25](https://github.com/greg676/vivado_neorv32/pull/25)** | **Pt-only** `pvla_mig7_top`: MIG7 **256 MB** @ `0x20000000` in front of the same 4 KiB FT601 PHY. Catalog PVLA stays BRAM. Au unchanged (no DDR). SRAM / RAM bitstream only. |

Earlier Pt loopback / sampler / PulseView-sim / catalog work is [#1](https://github.com/greg676/vivado_neorv32/pull/1)–[#8](https://github.com/greg676/vivado_neorv32/pull/8). Use the Au PHY (#18+) for silicon.

## SRAM, not QSPI

Every Au and Pt LA load in this work is **RAM**: `openFPGALoader --write-sram` or Vivado `program_ram`. No `write_cfgmem`, no `.mcs`, no flash. Reload SRAM for each test.

## NeoRV32 is not rewritten

The RISC-V SoC, debug console, and Platinum platform README stay as they are. LA / FT601 / PVLA tops **do not instantiate NeoRV32**. Pt DDR3 (#25) is a fabric AXI master + MIG, no CPU in the BD.

## Also in this repo

- [`platforms/alchitry-platinum-v2/`](platforms/alchitry-platinum-v2/README.md) — NeoRV32 on Pt V2 (codec, display, JTAG)
- [`applications/loom/`](applications/loom/expanded/README.md) — LOOM audio design docs (not the capture path)
- [`infrastructure/ads-mcp/`](infrastructure/ads-mcp/expanded/README.md) — ADS+MCP tooling
