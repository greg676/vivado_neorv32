# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# ── pvla_mig7_top.xdc ──────────────────────────────────────────
# Board clock, reset, LEDs. FT601 pins come from IP-scoped Ft+ XDC.
# DDR3 PACKAGE_PIN lives in the MIG IP (neorv_basic_plus pinout).
# Do not program QSPI from this file.

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN W19 [get_ports clk]
create_clock -period 10.000 -name clk_100mhz -waveform {0.000 5.000} [get_ports clk]

set_property IOSTANDARD LVCMOS33 [get_ports rst_n]
set_property PACKAGE_PIN N15 [get_ports rst_n]

set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_property PACKAGE_PIN P19 [get_ports {led[0]}]
set_property PACKAGE_PIN P20 [get_ports {led[1]}]
set_property PACKAGE_PIN T21 [get_ports {led[2]}]
set_property PACKAGE_PIN R19 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN U21 [get_ports {led[5]}]
set_property PACKAGE_PIN T20 [get_ports {led[6]}]
set_property PACKAGE_PIN W20 [get_ports {led[7]}]

# ft_clk (from FT601) is async to the board oscillator and to MIG ui_clk.
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks clk_100mhz] \
  -group [get_clocks -include_generated_clocks ft_clk]
