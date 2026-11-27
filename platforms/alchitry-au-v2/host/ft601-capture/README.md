# FT601 LA capture (Alchitry Au V2 + Ft+)

Host IN of packed 8-bit samples from `la_capture_top`. Dual 4 KiB BRAM
ping-pong sits in front of the PR #18 PHY (Lucid DATA-before-WR, **4 KiB
write bursts**, NEVER RD) so the sampler does not stall on TXE.

Each USB 32-bit word is four little-endian samples:

`[7:0]=t+0  [15:8]=t+1  [23:16]=t+2  [31:24]=t+3`

Default bitstream is an 8-bit wrapping counter (D0..D7). Writes a sigrok v2
`.sr` PulseView opens. Do not copy `.sr` zips into Project `docs/`.

```bash
python3 ft601_capture.py --self-test
# SRAM-load bitstreams/la_capture_top_v2.bit first (never --write-flash):
python3 ft601_capture.py --backend d3xx --bytes 16384 --chunk-bytes 4096 \
    --sr /tmp/au-la-counter.sr --dump /tmp/au-la-counter.raw
# 16 MiB D3XX IN throughput: use the C overlapped streamer, not 16 KiB Python.
# (from host/ft601-loopback, after `make d3xx`)
../ft601-loopback/ft601_loopback_d3xx --packed-counter --bytes 16777216 \
    --chunk-bytes 262144 --nflight 4
```
