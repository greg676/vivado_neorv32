#!/usr/bin/env python3
"""Structural check for the PVLA Vivado IP (no Vivado required)."""
from __future__ import annotations

import re
import sys
from pathlib import Path

IP = Path(__file__).resolve().parents[1]
REPO = IP.parents[1]
PLAT = REPO / "platforms" / "alchitry-platinum-v2"
AU = REPO / "platforms" / "alchitry-au-v2"

# First-batch vs production DATA[0:13] — docs/ft601-pin-map.md
ALPHA_DATA_0_13 = [
    "AB13", "AA13", "AA11", "AA10", "AB12", "AB11", "Y14", "W14",
    "AB15", "AA15", "W16", "W15", "AB17", "AB16",
]
V2_DATA_0_13 = [
    "R14", "P14", "R16", "P15", "R17", "P16", "P17", "N17",
    "W17", "V17", "T18", "R18", "AB20", "AA19",
]
AU_DATA_0_13 = [
    "T8", "T7", "T10", "T9", "T5", "R5", "T12", "R12",
    "R7", "R6", "T13", "R13", "R8", "P8",
]
PT_COMMON = {
    "ft_clk": "H4",
    "ft_wakeup": "AB22",
    "ft_reset": "AB21",
    "ft_rxf": "N2",
    "ft_txe": "P2",
    "ft_oe": "AB18",
    "ft_rd": "AA18",
    "ft_wr": "E3",
}
AU_COMMON = {
    "ft_clk": "D4",
    "ft_wakeup": "N6",
    "ft_reset": "M6",
    "ft_rxf": "L2",
    "ft_txe": "L3",
    "ft_oe": "P9",
    "ft_rd": "N9",
    "ft_wr": "J1",
}

ERRORS: list[str] = []


def err(msg: str) -> None:
    ERRORS.append(msg)


def must_exist(path: Path) -> None:
    if not path.is_file():
        err(f"missing {path}")


def parse_pkg_pins(xdc: Path) -> dict[str, str]:
    text = xdc.read_text()
    pins: dict[str, str] = {}
    for m in re.finditer(
        r"set_property\s+PACKAGE_PIN\s+(\S+)\s+\[get_ports\s+(\{[^}]+\}|[^\]]+)\]",
        text,
    ):
        pin, port = m.group(1), m.group(2).strip().strip("{}")
        pins[port] = pin
    return pins


def check_xdc_map(xdc: Path, data_0_13: list[str], common: dict[str, str]) -> None:
    pins = parse_pkg_pins(xdc)
    for port, expect in common.items():
        got = pins.get(port)
        if got != expect:
            err(f"{xdc.name}: {port} pin {got!r} != {expect!r}")
    for i, expect in enumerate(data_0_13):
        port = f"ft_data[{i}]"
        got = pins.get(port)
        if got != expect:
            err(f"{xdc.name}: {port} pin {got!r} != {expect!r}")


def main() -> int:
    hdl = [
        "hdl/pvla.v",
        "hdl/pvla_capture.v",
        "hdl/pvla_axi_lite.v",
        "hdl/pvla_word_packer.v",
        "hdl/pvla_internal_src.v",
    ]
    xdc = [
        "xdc/ftplus_ft601_pt_alpha.xdc",
        "xdc/ftplus_ft601_pt_v2.xdc",
        "xdc/ftplus_ft601_au_v2.xdc",
        "xdc/ftplus_ft601_timing.xdc",
        "xdc/ftplus_ft601_impl.xdc",
        "xdc/br_bank_a_8ch.xdc",
    ]
    meta = [
        "component.xml",
        "pvla_vivado_ip.tcl",
        "xgui/pvla_v1_0.tcl",
        "bd/bd.tcl",
        "pvla_v1_0_upgrade.tcl",
        "README.md",
    ]
    for rel in hdl + xdc + meta:
        must_exist(IP / rel)

    must_exist(PLAT / "tcl" / "pvla_bd_example.tcl")
    must_exist(AU / "tcl" / "pvla_bd_example.tcl")
    must_exist(AU / "rtl" / "ft601" / "ft601_sync_fifo.v")
    must_exist(AU / "rtl" / "ft601" / "ft601_reset.v")

    phy = (AU / "rtl" / "ft601" / "ft601_sync_fifo.v").read_text()
    if "ALWAYS_DRIVE" not in phy:
        err("Au PHY missing ALWAYS_DRIVE (need PR #18 Lucid WR)")
    if "TX_BURST_WORDS" not in phy and "1024" not in phy:
        err("Au PHY missing 4 KiB burst (TX_BURST_WORDS/1024)")
    if "ST_TX_SETUP" in phy:
        err("Au PHY still has ST_TX_SETUP; Lucid WR dropped that state")

    top = (IP / "hdl" / "pvla.v").read_text()
    for param in (
        "C_NUM_CH", "C_SAMPLE_MHZ", "C_SAMPLE_DIV", "C_SAMPLE_CLK_SRC",
        "C_INPUT_PATH", "C_PAD_MODE", "C_PRETRIG_SAMPLES", "C_PHY",
        "C_BOARD", "C_HAS_AXI", "C_INCLUDE_BR_XDC",
    ):
        if f"parameter integer {param}" not in top:
            err(f"pvla.v missing parameter {param}")
    if "parameter integer C_BOARD           = 2" not in top \
            and "parameter integer C_BOARD = 2" not in top:
        if "C_BOARD           = 2" not in top:
            err("pvla.v default C_BOARD should be AU_V2 (2)")
    if "C_SAMPLE_MHZ      = 200" not in top and "C_SAMPLE_MHZ = 200" not in top:
        err("pvla.v default C_SAMPLE_MHZ should be 200 (8ch advertised, 50 Mword/s USB)")
    if "probe_i" not in top:
        err("pvla.v missing probe_i")
    if "s_axi_awaddr" not in top:
        err("pvla.v missing AXI-lite")
    top_code = "\n".join(
        ln.split("//", 1)[0] for ln in top.splitlines() if not ln.lstrip().startswith("//")
    )
    if re.search(r"mig7|MIG7|ddr3_ui", top_code, re.I):
        err("pvla.v must not instantiate MIG/DDR3")
    if re.search(r"\bneorv32\b", top_code, re.I):
        err("pvla.v must not instantiate NeoRV32")

    packer = (IP / "hdl" / "pvla_word_packer.v").read_text()
    for token in (
        "g_pack4", "g_pack8", "g_pack16", "word_o", "C_NUM_CH",
        "word_o[31:28]", "word_o[31:24]", "word_o[31:16]",
    ):
        if token not in packer:
            err(f"pvla_word_packer.v missing {token}")
    if "IDDR" in packer:
        err("simple packer must not use IDDR (SDR first cut)")

    cap = (IP / "hdl" / "pvla_capture.v").read_text()
    if "C_PHY" not in cap or "ft601_sync_fifo" not in cap:
        err("pvla_capture.v must wrap FT601 PHY")
    if "m_axis_tdata" not in cap:
        err("pvla_capture.v missing STREAM master")
    if "pvla_word_packer" not in cap:
        err("pvla_capture.v must instantiate the visible word packer")
    if ".ALWAYS_DRIVE   (C_PAD_MODE)" not in cap and "ALWAYS_DRIVE   (C_PAD_MODE)" not in cap:
        if "C_PAD_MODE" not in cap or "ALWAYS_DRIVE" not in cap:
            err("pvla_capture.v must pass C_PAD_MODE as PHY ALWAYS_DRIVE")
    if "rx_ready (1'b0)" not in cap and ".rx_ready (1'b0)" not in cap:
        err("pvla_capture.v must keep RX unused (rx_ready=0) for TX-only host IN")
    if "TX_BURST_WORDS" not in cap:
        err("pvla_capture.v must set TX_BURST_WORDS (4 KiB bursts)")
    if "ft601_fwft_fifo" in cap:
        err("pvla_capture.v must not use the old echo FWFT starve path")
    if "la_capture_ctrl" in cap:
        err("pvla_capture.v must not pull the old platinum echo stack")

    timing = (IP / "xdc" / "ftplus_ft601_timing.xdc").read_text()
    if "0.900" not in timing:
        err("timing XDC must use PR #18 0.90 ns output max delay")

    check_xdc_map(IP / "xdc" / "ftplus_ft601_pt_alpha.xdc", ALPHA_DATA_0_13, PT_COMMON)
    check_xdc_map(IP / "xdc" / "ftplus_ft601_pt_v2.xdc", V2_DATA_0_13, PT_COMMON)
    check_xdc_map(IP / "xdc" / "ftplus_ft601_au_v2.xdc", AU_DATA_0_13, AU_COMMON)

    br = (IP / "xdc" / "br_bank_a_8ch.xdc").read_text()
    if "probe_i[0]" not in br or "B13" not in br:
        err("br_bank_a_8ch.xdc should constrain probe_i, not la_in")

    xml = (IP / "component.xml").read_text()
    for token in (
        "greg676", "pvla", "C_NUM_CH", "C_INPUT_PATH", "C_PAD_MODE",
        "C_SAMPLE_DIV", "C_SAMPLE_CLK_SRC", "probe_i",
        "ftplus_ft601_pt_alpha.xdc", "ftplus_ft601_pt_v2.xdc",
        "ftplus_ft601_au_v2.xdc",
        "xgui/pvla_v1_0.tcl", "SCOPED_TO_REF",
        "alchitry-au-v2/rtl/ft601/ft601_sync_fifo.v",
        "hdl/pvla_word_packer.v", "hdl/pvla_internal_src.v",
        "4 ch (8 samples/word)", "IOBUF 245",
        "400 MS/s (4ch)", "200 MS/s (8ch)", "100 MS/s (16ch)",
        "50 Mword/s USB",
    ):
        if token not in xml:
            err(f"component.xml missing {token!r}")
    if "xilinx:fileInfo" in xml:
        err("component.xml must not use nested xilinx:fileInfo (IP_Flow 19-395)")
    if "alchitry-platinum-v2/rtl/la/" in xml:
        err("component.xml still references the old platinum LA stack")
    if "alchitry-platinum-v2/rtl/ft601/" in xml:
        err("component.xml still references the old platinum echo PHY")

    gui = (IP / "xgui" / "pvla_v1_0.tcl").read_text()
    for token in (
        "C_NUM_CH", "C_PHY", "C_BOARD", "C_INPUT_PATH", "C_PAD_MODE",
        "C_SAMPLE_DIV", "C_SAMPLE_CLK_SRC", "init_gui", "usb_Mword",
        "400/200/100", "50 Mword/s",
    ):
        if token not in gui:
            err(f"xgui missing {token}")

    pkg = (IP / "pvla_vivado_ip.tcl").read_text()
    if "ipx::package_project" not in pkg:
        err("packager must call ipx::package_project (NEORV32 pattern)")
    if "scoped_to_ref" not in pkg:
        err("packager must SCOPED_TO_REF XDCs")
    if "alchitry-au-v2" not in pkg:
        err("packager must reference Au PHY RTL")
    if "AU_V2" not in pkg:
        err("packager GUI must offer AU_V2 board pinout")
    if "pvla_word_packer.v" not in pkg:
        err("packager must include the visible word packer")
    if "C_PAD_MODE" not in pkg:
        err("packager GUI must offer C_PAD_MODE (IOBUF vs ALWAYS_DRIVE)")
    if "400/200/100" not in pkg and "400 MS/s" not in pkg:
        err("packager GUI must advertise 400/200/100 MS/s, not 800/400/200")

    for example_path in (
        PLAT / "tcl" / "pvla_bd_example.tcl",
        AU / "tcl" / "pvla_bd_example.tcl",
    ):
        example = example_path.read_text()
        code_lines = "\n".join(
            ln for ln in example.splitlines() if not ln.lstrip().startswith("#")
        )
        if re.search(r"create_bd_net\s+", code_lines) and "ft_" in code_lines:
            err(f"{example_path.name}: example BD must not create FT601 nets")
        if "greg676:user:pvla:1.0" not in example:
            err(f"{example_path}: missing PVLA VLNV")
        if "make_bd_pins_external -name probe_i" not in example:
            err(f"{example_path}: must export probe_i")
        if "must be 4, 8, or 16" not in example:
            err(f"{example_path.name}: example BD must allow 4/8/16 channels")
        if re.search(r"create_bd_cell\s+-type\s+ip\s+.*mig", example, re.I):
            err(f"{example_path}: must not instantiate MIG")
        if re.search(r"create_bd_cell\s+.*neorv32", code_lines, re.I):
            err(f"{example_path}: must not instantiate NeoRV32")

    golden = IP / "scripts" / "tb_pvla_word_packer.py"
    must_exist(golden)
    if not ERRORS:
        import runpy
        ns = runpy.run_path(str(golden), run_name="pvla_pack_golden")
        if "main" in ns and ns["main"]():
            err("tb_pvla_word_packer.py golden failed")

    if ERRORS:
        print("PVLA IP check FAILED:")
        for e in ERRORS:
            print(f"  - {e}")
        return 1
    print("PVLA IP check PASS")
    print(f"  IP dir : {IP}")
    print("  VLNV   : greg676:user:pvla:1.0")
    print("  Packer : 4/8/16 ch -> 32-bit USB word (visible RTL)")
    print("  PHY    : Au PR #18/#19 Lucid WR, 4 KiB, IOBUF default, RX unused")
    print("  XDC    : PT_ALPHA / PT_V2 / AU_V2 DATA[0:13] match pin maps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
