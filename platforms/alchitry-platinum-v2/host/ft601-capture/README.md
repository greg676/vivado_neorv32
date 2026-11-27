# FT601 logic-analyzer capture dump

Phase 2 of the Pt V2 logic analyzer: stream packed 8-bit samples over USB 3.

`8 × LVCMOS33 Br pins → sampler → packer → FT601 TX → host dump`

This is a **separate bitstream** from NeoRV32 and from the FT601 loopback top.
Loopback ([host/ft601-loopback](../ft601-loopback/)) stays the USB proof.
Do not plug hardware until this design is in a PR and you have a local Vivado bitstream.

## Packing

Four samples per little-endian 32-bit FT601 word, oldest in the LSB:

| bits | sample |
|---|---|
| `[7:0]` | t+0 |
| `[15:8]` | t+1 |
| `[23:16]` | t+2 |
| `[31:24]` | t+3 |

One byte per sample, 8 channels. 100 MS/s = 100 MB/s; 200 MS/s (DDR @ 100 MHz `ft_clk`) = 200 MB/s.

## FPGA bitstream (separate top, NeoRV32 untouched)

From `platforms/alchitry-platinum-v2`:

```bash
vivado -mode batch -source tcl/rebuild_la_capture.tcl
# then in Vivado: Generate Bitstream
```

Defaults:

| Knob | Default | Alternate |
|---|---|---|
| Pinout | `pt_alpha` (first-batch Pt) | `v2` production Pt |
| Rate | `100` MS/s SDR | `200` MS/s DDR |
| Source | `0` counter pattern | `1` walking-one, `2` live Br pins |

```tcl
set ft601_pinout "v2"
set la_sample_mhz 200
set la_source 0
source tcl/rebuild_la_capture.tcl
```

Live inputs (FPGA bank 16, `IOSTANDARD LVCMOS33` only):

| ch | Br | FPGA |
|---|---|---|
| 0–3 | A33–A36 | B13, A14, C13, A13 |
| 4–7 | A39–A42 | C17, B18, D17, B17 |

A host write of a 32-bit word overwrites the source mux (`[1:0]`: 0=counter, 1=walking, 2=live) without rebuilding.

LEDs: `[0]` board-clk heartbeat, `[1]` `ft_clk` heartbeat, `[2]` out of reset, `[3]` FIFO has data, `[4]` FIFO full, `[5]` overflow sticky, `[6]` live source, `[7]` TX beat.

The DDR3 stub is a **parallel tap** (word counter only). It is not in the USB path.

## Host dump

Pattern checker (no SDK, no board):

```bash
make selftest
python3 ft601_capture.py --self-test
```

Hardware (SDK installed — same D3XX notes as the loopback tool):

```bash
make d3xx D3XX_DIR=/opt/ftdi/d3xx
./ft601_capture --bytes 16777216 --dump capture.bin

# or
export FTD3XX_LIB=/opt/ftdi/d3xx/libftd3xx.so
python3 ft601_capture.py --bytes 16777216 --dump capture.bin --pattern counter
```

| Flag | Meaning |
|---|---|
| `--bytes N` | Multiple of 4. Default 16 MiB. |
| `--dump FILE` | Raw packed little-endian words. |
| `--pattern counter\|walking\|none` | Verify on-FPGA pattern. |
| `--source N` | Write mux select before reading. |
| `--self-test` | No hardware. |

Each USB read prints a timestamped block (`t=… block=… bytes=… first=…`). Exit `0` is PASS.

Bring-up order once you have a bitstream: FPGA test pattern first, then live pins.

## RTL simulation (no Vivado)

```bash
make -C ../../sim/la
```

Proves packer + FT601 TX words at 100 MS/s and 200 MS/s.

## Out of scope (later)

Trigger engine, 4-ch 400 MS/s ISERDES, DDR3 pre-trigger DMA, libsigrok / PulseView, custom PCB.
