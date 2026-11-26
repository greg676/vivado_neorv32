# FT601 LA capture (Alchitry Au V2 + Ft+)

Host IN of packed 8-bit samples from `la_capture_top`. The FPGA uses the
PR #18 PHY: Lucid DATA-before-WR, **4 KiB write bursts**, NEVER RD.

Each USB 32-bit word is four little-endian samples:

`[7:0]=t+0  [15:8]=t+1  [23:16]=t+2  [31:24]=t+3`

Default bitstream is an 8-bit wrapping counter (D0..D7). Writes a sigrok v2
`.sr` PulseView opens. Do not copy `.sr` zips into Project `docs/`.

```bash
python3 ft601_capture.py --self-test
# SRAM-load bitstreams/la_capture_top_v2.bit first (never --write-flash):
python3 ft601_capture.py --backend d3xx --bytes 16384 --chunk-bytes 4096 \
    --sr /tmp/au-la-counter.sr --dump /tmp/au-la-counter.raw
```
