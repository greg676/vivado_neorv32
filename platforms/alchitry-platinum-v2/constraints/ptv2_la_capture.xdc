# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# ── ptv2_la_capture.xdc ─────────────────────────────────────────
# 8 × LVCMOS33 analyzer inputs on Br BOTTOM Bank A (FPGA bank 16).
# Pair with the FT601 pin-map XDC + ptv2_ft601_loopback.xdc (clk/rst/LED
# / FT601 timing). Do not use this file on the loopback-only top.
#
#   ch  Br pin   FPGA   bank  IOSTANDARD   notes
#   0   A33      B13    16    LVCMOS33
#   1   A34      A14    16    LVCMOS33
#   2   A35      C13    16    LVCMOS33
#   3   A36      A13    16    LVCMOS33
#   4   A39      C17    16    LVCMOS33     MRCC N
#   5   A40      B18    16    LVCMOS33     SRCC N
#   6   A41      D17    16    LVCMOS33     MRCC P  (data this phase)
#   7   A42      B17    16    LVCMOS33     SRCC P

set_property PACKAGE_PIN B13 [get_ports {la_in[0]}]
set_property PACKAGE_PIN A14 [get_ports {la_in[1]}]
set_property PACKAGE_PIN C13 [get_ports {la_in[2]}]
set_property PACKAGE_PIN A13 [get_ports {la_in[3]}]
set_property PACKAGE_PIN C17 [get_ports {la_in[4]}]
set_property PACKAGE_PIN B18 [get_ports {la_in[5]}]
set_property PACKAGE_PIN D17 [get_ports {la_in[6]}]
set_property PACKAGE_PIN B17 [get_ports {la_in[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {la_in[*]}]

# Live pins are asynchronous to ft_clk. The IOB FF / IDDR is the sample
# element; do not time them as a synchronous bus.
set_false_path -from [get_ports {la_in[*]}]
