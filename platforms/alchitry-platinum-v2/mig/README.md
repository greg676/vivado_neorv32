# Pt V2 MIG7 pinout (256 MB DDR3)

PVLA does **not** vendor a new MIG pin file. Reuse the proven Pt V2 256 MB controller:

| | |
|---|---|
| Part | XC7A100T-2FGG484 |
| Memory | MT41K128M16, 16-bit, 256 MB |
| Map | `0x2000_0000` … `0x2FFF_FFFF` |
| `ui_clk` | ~100 MHz (DDR3-800, 4:1) |
| `sys_clk_i` | 100 MHz from `clk_wiz` |
| `clk_ref_i` | 200 MHz (IDELAYCTRL) |

DDR3 `PACKAGE_PIN`s live **inside** the MIG IP (same as a DIMM pin file). Do not add them to a user XDC.

## Get `mig_b.prj`

Copy `mig_b.prj` from a prior Pt V2 Vivado project that already brought up this DDR3:

```bash
cp <proj>.gen/sources_1/bd/*/ip/*mig_7series*/mig_b.prj \
   platforms/alchitry-platinum-v2/mig/mig_b.prj
```

`tcl/pvla_mig7_bd.tcl` also accepts `mig/mig_pt_v2.prj` as a fallback name.

Then:

```bash
cd platforms/alchitry-platinum-v2
vivado -mode batch -source tcl/pvla_mig7_bd.tcl
```

Alchitry Labs `mig_plus.prj` is **Au+ FTG256**, not this FGG484 part. Do not use it here.

Au V2 has **no DDR**. This directory is Pt-only. This tree does not include NeoRV32.
