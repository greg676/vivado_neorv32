#!/usr/bin/env python3
"""Structural check: Pt MIG7 capture top. No Vivado required."""
from __future__ import annotations

import re
import sys
from pathlib import Path

PLAT = Path(__file__).resolve().parents[1]
REPO = PLAT.parents[1]
AU = REPO / "platforms" / "alchitry-au-v2"
IP = REPO / "ip" / "pvla"
ERRORS: list[str] = []


def err(msg: str) -> None:
    ERRORS.append(msg)


def must_exist(path: Path) -> None:
    if not path.is_file():
        err(f"missing {path}")


def main() -> int:
    for rel in (
        "rtl/la/la_dc_fwft.v",
        "rtl/la/la_ddr3_axi_buf.v",
        "rtl/la/pvla_mig7_capture_core.v",
        "rtl/la/pvla_mig7_top.v",
        "sim/la/axi_sram_slave.v",
        "sim/la/tb_la_ddr3_axi_buf.v",
        "sim/la/tb_pvla_mig7_stream.v",
        "sim/la/Makefile",
        "tcl/pvla_mig7_bd.tcl",
        "tcl/rebuild_pvla_mig7.tcl",
        "constraints/pvla_mig7_top.xdc",
        "mig/README.md",
    ):
        must_exist(PLAT / rel)

    must_exist(AU / "rtl" / "ft601" / "ft601_sync_fifo.v")
    must_exist(AU / "rtl" / "la" / "la_pingpong_bram.v")

    # Au must not grow a DDR capture top.
    if (AU / "rtl" / "la" / "pvla_mig7_top.v").exists():
        err("Au must not have pvla_mig7_top (no DDR on Au)")
    if (AU / "tcl" / "pvla_mig7_bd.tcl").exists():
        err("Au must not have pvla_mig7_bd.tcl")

    core = (PLAT / "rtl/la/pvla_mig7_capture_core.v").read_text()
    if "ft601_sync_fifo" not in core:
        err("capture core must keep the 4 KiB FT601 PHY")
    if "ALWAYS_DRIVE" not in core or "TX_BURST_WORDS" not in core:
        err("PHY instance must be ALWAYS_DRIVE / TX_BURST_WORDS=1024")
    if "la_pingpong_bram" not in core:
        err("capture core must keep dual 4 KiB ping-pong in front of the PHY")
    core_code = "\n".join(
        ln.split("//", 1)[0] for ln in core.splitlines() if not ln.lstrip().startswith("//")
    )
    if re.search(r"neorv32_vivado_ip|module\s+neorv", core_code, re.I):
        err("capture core must not instantiate NeoRV32")

    phy = (AU / "rtl/ft601/ft601_sync_fifo.v").read_text()
    if "ALWAYS_DRIVE" not in phy or "TX_BURST_WORDS" not in phy:
        err("Au PHY must remain 4 KiB Lucid WR")

    buf = (PLAT / "rtl/la/la_ddr3_axi_buf.v").read_text()
    if "32'h2000_0000" not in buf and "32'h20000000" not in buf:
        err("AXI buffer default base must be 0x20000000")
    if "128" not in buf:
        err("AXI buffer should be 128-bit toward MIG")

    bd = (PLAT / "tcl/pvla_mig7_bd.tcl").read_text()
    code = "\n".join(ln for ln in bd.splitlines() if not ln.lstrip().startswith("#"))
    if "mig_7series" not in bd:
        err("pvla_mig7_bd.tcl must instantiate MIG7")
    if re.search(r"create_bd_cell\s+.*neorv32", code, re.I):
        err("pvla_mig7_bd.tcl must not instantiate NeoRV32")
    if "0x20000000" not in bd or "256M" not in bd:
        err("BD must map 256 MB at 0x20000000")
    if re.search(r"write_cfgmem|program_hw_cfgmem|--write-flash", bd, re.I):
        err("BD tcl must not program QSPI")

    rebuild = (PLAT / "tcl/rebuild_pvla_mig7.tcl").read_text()
    if re.search(r"write-flash|program_flash", rebuild, re.I):
        err("rebuild tcl must not program QSPI")
    if "ft601_sync_fifo.v" not in rebuild:
        err("rebuild must reference the Au 4 KiB PHY")

    xdc = (PLAT / "constraints/pvla_mig7_top.xdc").read_text()
    if "PACKAGE_PIN W19" not in xdc:
        err("top XDC must place board clk on W19")
    if re.search(r"PACKAGE_PIN.*DDR3", xdc, re.I):
        err("top XDC must not pin DDR3 (MIG owns those)")

    # Catalog IP stays BRAM-only.
    pvla = (IP / "hdl/pvla.v").read_text()
    top_code = "\n".join(
        ln.split("//", 1)[0] for ln in pvla.splitlines() if not ln.lstrip().startswith("//")
    )
    if re.search(r"mig7|MIG7|ddr3_ui", top_code, re.I):
        err("pvla.v must still not instantiate MIG")
    example = (PLAT / "tcl/pvla_bd_example.tcl").read_text()
    ex_code = "\n".join(ln for ln in example.splitlines() if not ln.lstrip().startswith("#"))
    if re.search(r"create_bd_cell\s+-type\s+ip\s+.*mig", ex_code, re.I):
        err("pvla_bd_example.tcl must stay BRAM/FT601-only")

    if ERRORS:
        print("PVLA MIG7 check FAILED:")
        for e in ERRORS:
            print(f"  - {e}")
        return 1
    print("PVLA MIG7 check PASS")
    print("  Pt top : pvla_mig7_top (MIG7 256 MB + 4 KiB PHY)")
    print("  Au     : no DDR capture top")
    print("  CPU    : none")
    print("  Flash  : RAM only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
