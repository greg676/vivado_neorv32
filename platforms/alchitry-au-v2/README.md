# Alchitry Au V2 + Ft+ FT601 245 loopback

Dedicated **32-bit 245 echo** for **Alchitry Au** (`xc7a35ticsg324-1`) and **Ft+ on TOP**.
Published **V2** pinout from Alchitry `au_ft_plus.xdc`. Does **not** instantiate NeoRV32.

Do **not** load a Pt / `xc7a100t` bitstream onto this part.

## Build

```bash
cd platforms/alchitry-au-v2
vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl
# bitstream: bitstreams/ft601_loopback_top_v2.bit
```

## SRAM load (Jetson / openFPGALoader)

```bash
# RAM only — never --write-flash / -f / .mcs / QSPI
openFPGALoader --detect
# confirm idcode artix a7 35t / xc7a35 each load
```

Reload SRAM for **each** test. Do **not** reuse the echo bitstream.

```bash
# TX-only (FPGA never RD). Then host IN only.
vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl -tclargs
# or:  set ft601_mode TX_ONLY  in a wrapper
openFPGALoader --fpga-part xc7a35tftg256 --write-sram bitstreams/ft601_tx_only_top_v2.bit
python3 host/ft601-loopback/ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384 --tx-only

# RX-only (FPGA RD while RXF). Then host OUT known pattern.
openFPGALoader --fpga-part xc7a35tftg256 --write-sram bitstreams/ft601_rx_only_top_v2.bit
python3 host/ft601-loopback/ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384 --rx-only

# Echo loopback (PR #18 PHY: Lucid DATA-before-WR, 4 KiB write bursts).
vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl
openFPGALoader --fpga-part xc7a35tftg256 --write-sram bitstreams/ft601_loopback_top_v2.bit
python3 host/ft601-loopback/ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 4096
```

## LA capture (pattern → 4 KiB TX bursts → PulseView `.sr`)

Dedicated top, same PHY. Host IN only. Writes a sigrok v2 `.sr` (keep zips out of Project `docs/`).

```bash
vivado -mode batch -source tcl/rebuild_la_capture.tcl
# bitstream: bitstreams/la_capture_top_v2.bit
openFPGALoader --fpga-part xc7a35tftg256 --write-sram bitstreams/la_capture_top_v2.bit
python3 host/ft601-capture/ft601_capture.py --backend d3xx --bytes 16384 --chunk-bytes 4096 \
    --sr /tmp/au-la-counter.sr
```
