# PVLA — fabric logic analyzer over FT601

Vivado IP that samples 1–8 LVCMOS33 probes in the FPGA and streams them to **PulseView** (libsigrok). First PHY is the Alchitry **Ft+** FT601 SuperSpeed FIFO. This is not AMD ILA / Vivado Hardware Manager.

This tree is **PVLA / FT601 only**. NeoRV32, LOOM, and other projects are not in this snapshot.

## Status (Au, live)

Alchitry **Au** `xc7a35t` + Ft+ V2. SRAM reload only. **No QSPI.** SuperSpeed `0403:601f` @ 5000M. Overlapped D3XX IN.

| Path | Rate | vs 381.47 MiB/s theoretical |
|---|---:|---:|
| Capture IN **sink** | **335 MiB/s** | 88% |
| Capture IN **verified** packed counter | **257 MiB/s** | 67% (`words_ok` consecutive, 0 bad) |
| TX-only sink (USB ceiling) | 335 MiB/s | 88% |

32-bit × 100 MHz `ft_clk` = 400 MB/s = **381.47 MiB/s**. Remaining verify-vs-sink gap is host memcpy, not the FPGA packer.

![PulseView 0.4.2: 8-bit packed counter from Au SRAM capture (D0 fastest … D7 slowest)](media/pulseview-counter.png)

PulseView **0.4.2** / sigrok-cli **0.7.2** open the host `.sr`. Simulated LAT3 → `.sr` is under `platforms/alchitry-platinum-v2/host/pulseview-sim/`.

## Hardware sandwich (stock)

```
Ft+ FT601Q  → USB 3 host
        │  top connector
FPGA (Au xc7a35t  or  Pt V2 XC7A100T + DDR3)
        │  bottom connector
Br (or later LA input board)
```

Ft+ stays on top. Bottom is the instrument. **SRAM / RAM bitstream only** — never `--write-flash`, `.mcs`, or QSPI.

## Layout

| Path | What |
|---|---|
| [`ip/pvla/`](ip/pvla/README.md) | Catalog IP `greg676:user:pvla:1.0` (BD GUI, 1–8 channels, Ft+ XDC scoped to the IP) |
| [`platforms/alchitry-au-v2/`](platforms/alchitry-au-v2/README.md) | Proven Au PHY + 335 MiB/s capture |
| [`platforms/alchitry-platinum-v2/`](platforms/alchitry-platinum-v2/README.md) | Pt loopback, sampler, optional MIG7 256 MB buffer |
| [`host/`](host/) | Canonical Au libusb/D3XX loopback + capture (symlink to the Au platform host) |

## Where to start

Clone **this snapshot** (tag `pvla`). A plain clone of `vivado_neorv32` is the SoC tree, not PVLA.

```bash
git clone --branch pvla --single-branch --depth 1 \
    https://github.com/greg676/vivado_neorv32.git pvla
cd pvla
```

Zip: https://github.com/greg676/vivado_neorv32/archive/refs/tags/pvla.zip

SRAM load (Au). Confirm `idcode` `0x362d093` / xc7a35 **every** reload:

```bash
openFPGALoader --fpga-part xc7a35tftg256 --write-sram \
    platforms/alchitry-au-v2/bitstreams/la_capture_top_v2.bit
# then overlapped D3XX IN, or write a PulseView .sr:
# python3 host/ft601-capture/ft601_capture.py \
#     --backend d3xx --bytes 16384 --chunk-bytes 4096 --sr /tmp/au-la.sr
# pulseview -c -D -i /tmp/au-la.sr
```

Do **not** load a Pt `xc7a100t` bitstream onto Au.

PVLA in Vivado: **Settings → IP → Repository →** `<clone>/ip`, drop **PVLA**, 1–8 channels, `C_BOARD=AU_V2`.

## SRAM, not QSPI

Every Au and Pt LA load in this work is **RAM**: `openFPGALoader --write-sram` or Vivado `program_ram`. No `write_cfgmem`, no `.mcs`, no flash. Reload SRAM for each test.

## NeoRV32 is not in this tree

The RISC-V SoC stays private. LA / FT601 / PVLA tops **do not instantiate NeoRV32**. Pt DDR3 (`pvla_mig7_top`) is a fabric AXI master + MIG, no CPU in the BD.
