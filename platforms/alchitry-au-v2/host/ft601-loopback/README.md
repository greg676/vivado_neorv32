# FT601 loopback host tool (Alchitry Au V2 + Ft+)

Same 32-bit 245 checker as the Pt loopback: incrementing `uint32` words, fail-closed.

```bash
python3 ft601_loopback.py --self-test
make selftest
# Echo (LOOPBACK bitstream SRAM-loaded; PR #18 4 KiB PHY):
python3 ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 4096
# TX-only bitstream already SRAM-loaded (never reuse echo .bit):
python3 ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384 --tx-only
# RX-only bitstream SRAM-loaded:
python3 ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384 --rx-only
```

Jetson **throughput** (replace 16 KiB Python one-shot). SRAM-load TX-only or dual-BRAM, never QSPI:

```bash
make d3xx D3XX_DIR=$HOME/ft601-host/d3xx/unpack/linux-arm-v8
# TX-only: overlapped FT_ReadPipeAsync, 256 KiB x 4 in flight (try 1 MiB too)
./ft601_loopback_d3xx --tx-only --bytes 16777216 --chunk-bytes 262144 --nflight 4
./ft601_loopback_d3xx --tx-only --bytes 16777216 --chunk-bytes 1048576 --nflight 4
# Dual-FIFO36 packed counter (must match TX-only rate):
./ft601_loopback_d3xx --packed-counter --bytes 16777216 --chunk-bytes 262144 --nflight 4
./ft601_loopback_d3xx --packed-counter --bytes 268435456 --chunk-bytes 1048576 --nflight 8
./ft601_loopback_d3xx --packed-counter --sink --bytes 268435456 --chunk-bytes 1048576 --nflight 8
# A/B vs old 16 KiB one-shot:
./ft601_loopback_d3xx --tx-only --bytes 16777216 --no-stream
```

`--backend d3xx` uses Linux D3XX after the usual FT60x session (see `host/common/ft601_usb.py`). Prints `first_8` words. `--tx-only` is host IN with no OUT. `--rx-only` is host OUT of the incrementing pattern, then IN of the FPGA's latched first-RX constant. Theoretical 32-bit × 100 MHz = **381.47 MiB/s**.
