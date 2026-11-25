# FT601 loopback host tool

Proves the USB 3 path on Alchitry Pt V2 + Ft+ (`FT601Q`, 32-bit 245 FIFO):

`Host → FT601 → FPGA FIFO → FT601 → Host`

The matcher **fails closed** on dropped words, bit swaps, odd/short USB transfers, and byte-enable mistakes (loopback echoes `BE=0xF` on every word).

**Preferred USB backend is libusb-1.0.** D3XX is optional.

## FPGA bitstream (separate top, NeoRV32 untouched)

From `platforms/alchitry-platinum-v2`:

```bash
# recreates vivado_project_ft601 and runs synth+impl (Vivado 2025.2)
vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl

# GUI: File → Open Project → vivado_project_ft601/ft601_loopback.xpr
# skip_impl 1 if you only want the project:
#   vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl -tclargs
#   (or set skip_impl 1 before sourcing)
```

Defaults:

| Knob | Default | Alternate |
|---|---|---|
| Pinout | `pt_alpha` (first-batch Pt, matches this repo's existing FT601 notes) | `v2` production Pt |
| Mode | `LOOPBACK` | `TX_COUNTER` |

```tcl
# production Pt V2 pinout
set ft601_pinout "v2"
# FPGA sources an incrementing counter (host --tx-only)
set ft601_mode "TX_COUNTER"
source tcl/rebuild_ft601_loopback.tcl
```

**Program RAM, not flash:**

```bash
vivado -mode batch -source tcl/program_ram.tcl -tclargs \
  bitstreams/ft601_loopback_top_pt_alpha.bit
```

Do not write SPI flash / `.mcs`. The NeoRV32 SoC bitstream is not in this design; swap back when you are done.

LEDs: `[0]` board-clk heartbeat, `[1]` `ft_clk` heartbeat (must blink — if not, FT601 CLK is dead), `[2]` `~ft_rxf` (lights when the FT601 RX FIFO has data for the FPGA to drain), `[3]` loopback FIFO has data, `[4]` FIFO full, `[5]` RX beat, `[6]` TX beat, `[7]` overflow sticky.

`ft_reset` follows the Pt button only (high when the button is up). SRAM load must not pulse RESET_N; do not press reset while testing.

## Host USB

libusb talks to VID `0403` PID `601f`. **Claim IF0 and IF1.** Send a 20-byte session-list command on EP **0x01**, then bulk data on EP **0x02** / **0x82**. EEPROM is already 245 FIFO 32-bit (1 channel). On jetson-edge that path wrote **13312 bytes** (`4+1024+4096+8192`, `rc=0`) after a USB device reset. Do **not** use vendor abort `0x40/0x00` (pipe error). No flash.

```bash
make selftest                 # no board, no USB
make hw                       # libusb binary: ./ft601_loopback
sudo apt install libusb-1.0-0-dev   # if the compile cannot find libusb.h
```

Sim gold (Icarus, no flash) lives in `../../sim/ft601/vectors/*.bin`. Replay on hardware:

```bash
python3 ft601_loopback.py --vector ../../sim/ft601/vectors/counter.bin --bytes 256
# or: ./ft601_loopback --vector ../../sim/ft601/vectors/walking.bin --bytes 256
```

See `../../sim/ft601/README.md`.

Linux udev (once): allow unprivileged access to the FT601. Example:

```
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="601f", MODE="0666"
```

Do **not** bind `ftdi_sio` to the FT601. The on-board FTDI UART (console) is a different interface — leave it alone. Do not unbind the Pt V2 USB-UART (that resets the FPGA).

### Optional D3XX / aarch64 (Jetson)

`ftdichip.com` ARM tarballs **403**. Use the China mirror, **1.0.16**, ELF aarch64:

```
https://www.ftdichip.cn/Drivers/D3XX/Linux/libftd3xx-linux-arm-v8-1.0.16.tgz
```

On jetson-edge the unpack is `~/ft601-host/d3xx/unpack/linux-arm-v8/` (`libftd3xx.so` + `ftd3xx.h`). x86_64 OpenClaw bench still has `/opt/ftdi/d3xx/libftd3xx.so` (header often missing → `make d3xx` fails).

Linux D3XX (FTDI `rw.c`): `FT_SetTransferParams` with `fNonThreadSafeTransfer`, then `FT_Create(0, FT_OPEN_BY_INDEX, …)`. `FT_WritePipeEx` / `FT_ReadPipeEx` use **fifo id 0**, not pipe `0x02`. Host open does `libusb_reset_device` first. **Do not use 64 KiB URBs** — Jetson times out; cap is **16384** (`--chunk-bytes`). After reset, D3XX tx-only **4+1024+4096+8192+16384 = 29700**. First 16 KiB W+R OK; 32 KiB+ short. Repeating toward 16 MiB fills the chip FIFO (~45 KiB) if the FPGA does not drain.

```bash
export FTD3XX_LIB=$HOME/ft601-host/d3xx/unpack/linux-arm-v8/libftd3xx.so
# or x86: export FTD3XX_LIB=/opt/ftdi/d3xx/libftd3xx.so
python3 ft601_loopback.py --backend d3xx --bytes 16777216
```

To compile the C D3XX binary, point `D3XX_DIR` at a full SDK unpack (`ftd3xx.h` **and** `libftd3xx.so`), then `make d3xx`.

## Build / run

```bash
make selftest
python3 ft601_loopback.py --self-test

make hw
./ft601_loopback --bytes 16777216 --chunk-bytes 16384
# or
python3 ft601_loopback.py --bytes 16777216          # libusb first
python3 ft601_loopback.py --backend d3xx --bytes 16777216
```

| Flag | Meaning |
|---|---|
| `--bytes N` | Multiple of 4. Default 16 MiB. |
| `--index N` | FT601 index if several `0403:601f`. |
| `--backend auto\|libusb\|d3xx` | Python only. Default `auto` = libusb then D3XX. |
| `--tx-only` | Read-only; needs `TX_COUNTER` bitstream. |
| `--timeout-ms N` | Pipe timeout. |
| `--chunk-bytes N` | Host URB size, multiple of 4. Default **16384**. |
| `--self-test` | No hardware. |

Exit `0` is PASS. Any mismatch, short/odd transfer, or incomplete byte count is FAIL (exit `1`).

## Reset recovery

1. Press the Pt V2 reset button. LED `[1]` should resume blinking (`ft_clk` back).
2. Re-run the host tool. A clean PASS after reset is recovery.

If open fails after reset, wait a couple of seconds for USB re-enumeration.

## Phase 2/3 (separate capture top)

Eight-channel sampler / trigger / BRAM dump is a **different bitstream**:
[../ft601-capture/README.md](../ft601-capture/README.md).
This loopback top is unchanged.

## RTL simulation (no Vivado)

```bash
make -C ../../sim/ft601
```
