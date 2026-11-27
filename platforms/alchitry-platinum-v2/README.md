# Alchitry Pt V2 — PVLA / FT601

Platinum (`xc7a100t`, FGG484) + Ft+ on TOP. **No NeoRV32 in this tree.** SRAM / RAM bitstream only (no QSPI).

| Path | What |
|---|---|
| `rtl/ft601/` | 32-bit 245 loopback PHY (earlier Pt bring-up) |
| `rtl/la/` | Sampler, packer, `pvla_mig7_top` (256 MB DDR3 capture buffer) |
| `constraints/` | Ft+ pins (PT_ALPHA / V2) and LA / MIG7 XDCs |
| `host/` | libusb loopback, capture, PulseView sim |
| `mig/` | How to reuse the proven 256 MB MIG7 pin file |
| `tcl/` | Loopback, LA capture, PVLA BD, MIG7 BD |

Proven SuperSpeed PHY and 335 MiB/s capture IN were measured on **Au**. Use `platforms/alchitry-au-v2/` for the working instrument. Pt DDR3 is the large buffer in front of that same 4 KiB PHY.

```bash
cd platforms/alchitry-platinum-v2
vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl
vivado -mode batch -source tcl/rebuild_la_capture.tcl
# optional large buffer (needs mig_b.prj — see mig/README.md):
vivado -mode batch -source tcl/pvla_mig7_bd.tcl
```
