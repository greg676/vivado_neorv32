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
openFPGALoader --fpga-part xc7a35t --write-sram bitstreams/ft601_loopback_top_v2.bit
```

## Host 16 KiB D3XX

Session (libusb) then D3XX 16384 bytes:

```bash
cd host/ft601-loopback
python3 ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384
```

Prints `words_ok` / `words_bad` and the first two failing `got`/`exp` words.
