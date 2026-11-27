# FT601 loopback host tool (Alchitry Au V2 + Ft+)

Same 32-bit 245 checker as the Pt loopback: incrementing `uint32` words, fail-closed.

```bash
python3 ft601_loopback.py --self-test
# on Jetson, after SRAM load of xc7a35t bitstream:
python3 ft601_loopback.py --backend d3xx --bytes 16384 --chunk-bytes 16384
```

`--backend d3xx` uses Linux D3XX after the usual FT60x session (see `host/common/ft601_usb.py`). Prints `words_ok` / `words_bad` and the first two failing `got`/`exp` words.
