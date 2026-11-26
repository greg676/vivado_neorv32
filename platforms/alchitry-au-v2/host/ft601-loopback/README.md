# FT601 loopback host tool (Alchitry Au V2 + Ft+)

Same 32-bit 245 checker as the Pt loopback: incrementing `uint32` words, fail-closed.

```bash
python3 ft601_loopback.py --self-test
# TX-only bitstream already SRAM-loaded (never reuse echo .bit):
python3 ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384 --tx-only
# RX-only bitstream SRAM-loaded:
python3 ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384 --rx-only
```

`--backend d3xx` uses Linux D3XX after the usual FT60x session (see `host/common/ft601_usb.py`). Prints `first_8` words. `--tx-only` is host IN with no OUT. `--rx-only` is host OUT of the incrementing pattern, then IN of the FPGA's latched first-RX constant.
