# PVLA — fabric logic analyzer over FT601

**Public LA tree:** [https://github.com/greg676/vivado_neorv32/tree/cursor/public-pvla-a68c](https://github.com/greg676/vivado_neorv32/tree/cursor/public-pvla-a68c)

Vivado IP that samples 1–8 LVCMOS33 probes in the FPGA and streams them to **PulseView** (libsigrok). First PHY is the Alchitry **Ft+** FT601 SuperSpeed FIFO. This is not AMD ILA / Vivado Hardware Manager.

## Status (Au, live)

Alchitry **Au** `xc7a35t` + Ft+ V2. SRAM reload only. **No QSPI.** SuperSpeed `0403:601f` @ 5000M. Overlapped D3XX IN.

| Path | Rate | vs 381.47 MiB/s theoretical |
|---|---:|---:|
| Capture IN **sink** ([#24](https://github.com/greg676/vivado_neorv32/pull/24)) | **335 MiB/s** | 88% |
| Capture IN **verified** packed counter | **257 MiB/s** | 67% (`words_ok` consecutive, 0 bad) |
| TX-only sink (USB ceiling, [#23](https://github.com/greg676/vivado_neorv32/pull/23)) | 335 MiB/s | 88% |

32-bit × 100 MHz `ft_clk` = 400 MB/s = **381.47 MiB/s**. Remaining verify-vs-sink gap is host memcpy, not the FPGA packer.

![PulseView 0.4.2: 8-bit packed counter from Au SRAM capture (D0 fastest … D7 slowest)](media/pulseview-counter.png)

PulseView **0.4.2** / sigrok-cli **0.7.2** open the host `.sr` ([#19](https://github.com/greg676/vivado_neorv32/pull/19)). Simulated LAT3 → `.sr` is on the LA snapshot under `platforms/alchitry-platinum-v2/host/pulseview-sim/`.

## Hardware sandwich (stock)

```
Ft+ FT601Q  → USB 3 host
        │  top connector
FPGA (Au xc7a35t  or  Pt V2 XC7A100T + DDR3)
        │  bottom connector
Br (or later LA input board)
```

Ft+ stays on top. Bottom is the instrument. **SRAM / RAM bitstream only** — never `--write-flash`, `.mcs`, or QSPI.

## Clone the PVLA tree

This snapshot is **PVLA / FT601 only** (`ip/pvla`, Au + Pt LA platforms, `host/`). NeoRV32 is not in it.

```bash
git clone -b cursor/public-pvla-a68c --single-branch \
    https://github.com/greg676/vivado_neorv32.git pvla
cd pvla
```

| Path | What |
|---|---|
| [`ip/pvla/`](https://github.com/greg676/vivado_neorv32/tree/cursor/public-pvla-a68c/ip/pvla) | Catalog IP `greg676:user:pvla:1.0` (BD GUI, 1–8 channels) |
| [`platforms/alchitry-au-v2/`](https://github.com/greg676/vivado_neorv32/tree/cursor/public-pvla-a68c/platforms/alchitry-au-v2) | Proven Au PHY + 335 MiB/s capture |
| [`platforms/alchitry-platinum-v2/`](https://github.com/greg676/vivado_neorv32/tree/cursor/public-pvla-a68c/platforms/alchitry-platinum-v2) | Pt loopback, sampler, optional MIG7 256 MB buffer |
| [`host/`](https://github.com/greg676/vivado_neorv32/tree/cursor/public-pvla-a68c/host) | Au libusb/D3XX loopback + capture |

SRAM load (Au). Confirm `idcode` `0x362d093` / xc7a35 **every** reload:

```bash
openFPGALoader --fpga-part xc7a35tftg256 --write-sram \
    platforms/alchitry-au-v2/bitstreams/la_capture_top_v2.bit
# python3 host/ft601-capture/ft601_capture.py \
#     --backend d3xx --bytes 16384 --chunk-bytes 4096 --sr /tmp/au-la.sr
# pulseview -c -D -i /tmp/au-la.sr
```

Do **not** load a Pt `xc7a100t` bitstream onto Au.

PVLA in Vivado: **Settings → IP → Repository →** `<clone>/ip`, drop **PVLA**, 1–8 channels, `C_BOARD=AU_V2`.

## Working RTL PRs

Au stack (SRAM, no CPU, no QSPI):

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
| **[#25](https://github.com/greg676/vivado_neorv32/pull/25)** | **Pt-only** `pvla_mig7_top`: MIG7 **256 MB** in front of the same PHY |

## SRAM, not QSPI

Every Au and Pt LA load in this work is **RAM**: `openFPGALoader --write-sram` or Vivado `program_ram`. No `write_cfgmem`, no `.mcs`, no flash. Reload SRAM for each test.

LA / FT601 / PVLA tops **do not instantiate NeoRV32**. Pt DDR3 is a fabric AXI master + MIG, no CPU in the BD.

## License

Original work in this repository — including **PVLA**, FT601 PHY, LA capture, host tools, and Alchitry platform glue — is **MIT**. See [`LICENSE`](LICENSE). Source files carry `SPDX-License-Identifier: MIT`.

**NeoRV32** remains **BSD-3-Clause**. It is not rewritten here. The CPU is used as a Vivado catalog IP; firmware includes its public C headers. The upstream license is copied verbatim at [`third_party/neorv32/LICENSE`](third_party/neorv32/LICENSE) ([stnolting/neorv32](https://github.com/stnolting/neorv32)).

Vivado-generated wrapper netlists keep their AMD/Xilinx copyright comments. RISC-V GNU toolchain binaries under `platforms/alchitry-platinum-v2/firmware/debug_console/tools/` keep their own licenses (not MIT).

Do not commit secrets (API keys, `.env`, SSH keys). See `.gitignore`.
