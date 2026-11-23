# FT601 logic-analyzer triggered capture

Phase 3 of the Pt V2 logic analyzer: edge trigger, BRAM circular pre-trigger,
post-trigger count, then a USB dump that includes the trigger position.

`8 × LVCMOS33 Br pins → sampler → test-pattern mux → trigger + BRAM → packer → FT601 TX → host`

This is a **separate bitstream** from NeoRV32 and from the FT601 loopback top.
Loopback ([host/ft601-loopback](../ft601-loopback/)) stays the USB proof.

No DDR3 MIG, no 4-channel ISERDES. PulseView import without hardware lives
in [../pulseview-sim](../pulseview-sim/README.md).

**Preferred USB backend is libusb-1.0.** D3XX is optional (`FTD3XX_LIB=/opt/ftdi/d3xx/libftd3xx.so`).

## Packing

Four samples per little-endian 32-bit FT601 word, oldest in the LSB:

| bits | sample |
|---|---|
| `[7:0]` | t+0 |
| `[15:8]` | t+1 |
| `[23:16]` | t+2 |
| `[31:24]` | t+3 |

One byte per sample, 8 channels. 100 MS/s = 100 MB/s; 200 MS/s (DDR @ 100 MHz `ft_clk`) = 200 MB/s.

## Host command (FPGA RX, one 32-bit word)

| bits | field |
|---|---|
| `[3:0]` | `0` nop `1` cfg `2` start `3` stop `4` force |
| `[5:4]` | source: `0` counter `1` walking `2` live |
| `[8:6]` | trigger channel 0–7 |
| `[10:9]` | edge: `0` rise `1` fall `2` both `3` immediate |
| `[31:16]` | post-trigger sample count (`0` = keep current / bitstream default) |

START applies the fields and arms the circular BRAM. STOP dumps whatever is in the buffer. FORCE fires while armed.

## Dump header (`LAT3`, 8 little-endian words) then payload

| word | meaning |
|---|---|
| 0 | MAGIC `32'h3354414C` (`LAT3`) |
| 1 | VERSION `1` |
| 2 | STATUS `[1:0]` source `[4:2]` ch `[6:5]` edge `[8]` triggered `[9]` overflow `[10]` aborted `[11]` immediate |
| 3 | `NSAMPLES` (real 8-bit samples; last word may be zero-padded to 4) |
| 4 | `TRIG_POS` sample index of the trigger, or `0xFFFFFFFF` if none |
| 5 | overflow count (pre-trigger samples overwritten during POST) |
| 6 | drop count (STOP / clobber-stop leftover post samples) |
| 7 | configured post-trigger count |

Then packed payload words. `TRIG_POS` is relative to the first sample of the payload.

## FPGA bitstream (separate top, NeoRV32 untouched)

From `platforms/alchitry-platinum-v2`:

```bash
vivado -mode batch -source tcl/rebuild_la_capture.tcl
# GUI: File → Open Project → vivado_project_la_capture/la_capture.xpr
```

Defaults:

| Knob | Default | Alternate |
|---|---|---|
| Pinout | `pt_alpha` (first-batch Pt) | `v2` production Pt |
| Rate | `100` MS/s SDR | `200` MS/s DDR |
| Source | `0` counter pattern | `1` walking-one, `2` live Br pins |
| BRAM depth | `4096` entries (not DDR3) | power of two |
| Post | `2048` samples | `--post` / `la_post` |
| Trigger | ch 0, rising | `la_trig_ch` / `la_trig_edge` |

```tcl
set ft601_pinout "v2"
set la_sample_mhz 200
set la_source 0
set la_buf_depth 4096
set la_post 2048
set la_trig_ch 0
set la_trig_edge 0
source tcl/rebuild_la_capture.tcl
```

**Program RAM, not flash:**

```bash
vivado -mode batch -source tcl/program_ram.tcl -tclargs \
  bitstreams/la_capture_top_pt_alpha.bit
```

Live inputs (FPGA bank 16, `IOSTANDARD LVCMOS33` only):

| ch | Br | FPGA |
|---|---|---|
| 0–3 | A33–A36 | B13, A14, C13, A13 |
| 4–7 | A39–A42 | C17, B18, D17, B17 |

The on-FPGA counter / walking-one mux is still there. Host START selects it without rebuilding.

LEDs: `[0]` board-clk heartbeat, `[1]` `ft_clk` heartbeat, `[2]` out of reset, `[3]` armed, `[4]` triggered / FIFO full, `[5]` overflow or drop, `[6]` live source, `[7]` dump done / TX beat.

The DDR3 stub is still a **parallel tap** (word counter only). Pre-trigger is BRAM. It is not in the USB path.

## Host dump

```bash
make selftest
python3 ft601_capture.py --self-test

make hw
./ft601_capture --source 0 --channel 0 --edge rise --post 2048 --dump capture.bin

python3 ft601_capture.py --source 0 --edge rise --post 2048 --dump capture.bin --pattern counter
# optional D3XX (library only on this bench):
export FTD3XX_LIB=/opt/ftdi/d3xx/libftd3xx.so
python3 ft601_capture.py --backend d3xx --source 0 --edge rise --post 2048
```

Same D3XX notes as the loopback tool: OpenClaw left `/opt/ftdi/d3xx/libftd3xx.so`; `ftd3xx.h` is not installed, so `make d3xx` needs a full SDK unpack into `/opt/ftdi/d3xx`.

| Flag | Meaning |
|---|---|
| `--source N` | 0=counter 1=walking 2=live |
| `--channel N` | Trigger channel 0–7 |
| `--edge rise\|fall\|both\|imm` | Edge mode |
| `--post N` | Post-trigger samples |
| `--stop` | Dump an armed capture without waiting for the edge |
| `--dump FILE` | Raw packed payload (header is printed, not stored) |
| `--pattern counter\|walking\|none` | Verify on-FPGA pattern |
| `--backend auto\|libusb\|d3xx` | Python only |
| `--self-test` | No hardware |

The tool writes START, reads the 32-byte header, then reads `ceil(NSAMPLES/4)` payload words. Exit `0` is PASS.

Bring-up order once you have a bitstream: FPGA test pattern + immediate/rising on the counter, then live pins.

## RTL simulation (no Vivado)

```bash
make -C ../../sim/la
```

Proves packer, edge detector, 100/200 MS/s triggered dumps, fall/both/STOP/overflow/force.

## Out of scope (later)

4-ch 400 MS/s ISERDES, DDR3 MIG pre-trigger DMA, a libsigrok hardware driver, custom PCB.
Simulated PulseView sessions: [../pulseview-sim](../pulseview-sim/README.md).
