# Vivado IP repository

Add this directory once:

**Settings → IP → Repository →** `<repo>/ip`

| VLNV | GUI | Notes |
|---|---|---|
| `greg676:user:pvla:1.0` | Channels 1–8, PHY, Ft+ board | PulseView logic analyzer. FT601 Lucid WR / 4 KiB bursts; pins in IP-scoped XDCs. |

Packaging: `ip/pvla/pvla_vivado_ip.tcl`. This tree does not vendor or rewrite NeoRV32.

License: **MIT**. See [`LICENSE`](../LICENSE).
