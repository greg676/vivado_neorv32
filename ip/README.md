# Vivado IP repository

Add this directory once:

**Settings → IP → Repository →** `<repo>/ip`

| VLNV | GUI | Notes |
|---|---|---|
| `greg676:user:pvla:1.0` | Channels 1–8, PHY, Ft+ board | PulseView logic analyzer. FT601 pins in IP-scoped XDCs. |
| `NEORV32:user:neorv32:*` | CPU / memory / peripherals | Packaged from the NEORV32 tree (`neorv32_vivado_ip.tcl`), not from this folder. Do not rewrite it. |

PVLA packaging (same flow as NEORV32): `ip/pvla/pvla_vivado_ip.tcl`.
