# FT601 loopback host tool

Proves the USB 3 path on Alchitry Pt V2 + Ft+ (`FT601Q`, 32-bit 245 FIFO):

`Host → FT601 → FPGA FIFO → FT601 → Host`

The matcher **fails closed** on dropped words, bit swaps, odd/short USB transfers, and byte-enable mistakes (loopback echoes `BE=0xF` on every word).

This repo does not already vendor D3XX. The tool talks to FTDI D3XX when the SDK is installed.

## FPGA bitstream (separate top, NeoRV32 untouched)

From `platforms/alchitry-platinum-v2`:

```bash
vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl
# then in Vivado: Generate Bitstream
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

Load the loopback `.bit` with the Alchitry Loader. The NeoRV32 SoC bitstream is not in this design; swap back when you are done.

LEDs: `[0]` board-clk heartbeat, `[1]` `ft_clk` heartbeat (must blink — if not, FT601 CLK is dead), `[2]` out of reset, `[3]` FIFO has data, `[4]` FIFO full, `[5]` RX beat, `[6]` TX beat, `[7]` overflow sticky.

## D3XX SDK

1. Download **FTD3XX** (not D2XX) from FTDI: https://ftdichip.com/drivers/d3xx-driver/
2. Unpack so `ftd3xx.h` and `libftd3xx.so` share a directory, e.g. `/opt/ftdi/d3xx`.
3. Linux udev (once): allow unprivileged access to VID `0403` PID `601f` (FT601). Example:

   ```
   SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="601f", MODE="0666"
   ```

4. Do **not** bind `ftdi_sio` to the FT601. The on-board FTDI UART (console) is a different interface — leave it alone. Do not unbind the Pt V2 USB-UART (that resets the FPGA).

VID/PID: FT601 = `0403:601f`. Ft+ EEPROM is already 245 FIFO, 32-bit.

## Build / run

Pattern checker (no SDK, no board):

```bash
make selftest
python3 ft601_loopback.py --self-test
```

Hardware (SDK installed):

```bash
make d3xx D3XX_DIR=/opt/ftdi/d3xx
./ft601_loopback --bytes 16777216

# or
export FTD3XX_LIB=/opt/ftdi/d3xx/libftd3xx.so
python3 ft601_loopback.py --bytes 16777216
```

| Flag | Meaning |
|---|---|
| `--bytes N` | Multiple of 4. Default 16 MiB. |
| `--index N` | D3XX device index. |
| `--tx-only` | Read-only; needs `TX_COUNTER` bitstream. |
| `--timeout-ms N` | Pipe timeout. |
| `--self-test` | No hardware. |

Exit `0` is PASS. Any mismatch, short/odd transfer, or incomplete byte count is FAIL (exit `1`).

## Reset recovery

1. Press the Pt V2 reset button. LED `[1]` should resume blinking (`ft_clk` back).
2. Re-run the host tool. A clean PASS after reset is recovery.

If `FT_Create` fails after reset, wait a couple of seconds for USB re-enumeration.

## RTL simulation (no Vivado)

```bash
make -C ../../sim/ft601
```
