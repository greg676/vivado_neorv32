# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# PVLA IP-scoped Ft+ FT601 pinout — first-batch Alchitry Pt (PT_ALPHA).
# Packaged with the IP and SCOPED_TO_REF pvla. PACKAGE_PIN follows the
# IP ports (ft_*), which the example BD TCL promotes to the wrapper with
# the same names. Do not add these pins to a user top XDC.
#
# DATA[0:13] = first-batch Bank B. Control / BE / DATA[14:31] match V2.
# Source: docs/ft601-pin-map.md

set_property PACKAGE_PIN H4 [get_ports ft_clk]
set_property IOSTANDARD LVCMOS33 [get_ports ft_clk]
create_clock -period 10.000 -name ft_clk -waveform {0.000 5.000} [get_ports ft_clk]

set_property PACKAGE_PIN AB22 [get_ports ft_wakeup]
set_property IOSTANDARD LVCMOS33 [get_ports ft_wakeup]

set_property PACKAGE_PIN AB21 [get_ports ft_reset]
set_property IOSTANDARD LVCMOS33 [get_ports ft_reset]

set_property PACKAGE_PIN N2 [get_ports ft_rxf]
set_property IOSTANDARD LVCMOS33 [get_ports ft_rxf]

set_property PACKAGE_PIN P2 [get_ports ft_txe]
set_property IOSTANDARD LVCMOS33 [get_ports ft_txe]

set_property PACKAGE_PIN AB18 [get_ports ft_oe]
set_property IOSTANDARD LVCMOS33 [get_ports ft_oe]

set_property PACKAGE_PIN AA18 [get_ports ft_rd]
set_property IOSTANDARD LVCMOS33 [get_ports ft_rd]

set_property PACKAGE_PIN E3 [get_ports ft_wr]
set_property IOSTANDARD LVCMOS33 [get_ports ft_wr]

set_property PACKAGE_PIN M2 [get_ports {ft_be[0]}]
set_property PACKAGE_PIN M1 [get_ports {ft_be[1]}]
set_property PACKAGE_PIN L1 [get_ports {ft_be[2]}]
set_property PACKAGE_PIN F3 [get_ports {ft_be[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ft_be[*]}]

set_property PACKAGE_PIN AB13 [get_ports {ft_data[0]}]
set_property PACKAGE_PIN AA13 [get_ports {ft_data[1]}]
set_property PACKAGE_PIN AA11 [get_ports {ft_data[2]}]
set_property PACKAGE_PIN AA10 [get_ports {ft_data[3]}]
set_property PACKAGE_PIN AB12 [get_ports {ft_data[4]}]
set_property PACKAGE_PIN AB11 [get_ports {ft_data[5]}]
set_property PACKAGE_PIN Y14  [get_ports {ft_data[6]}]
set_property PACKAGE_PIN W14  [get_ports {ft_data[7]}]
set_property PACKAGE_PIN AB15 [get_ports {ft_data[8]}]
set_property PACKAGE_PIN AA15 [get_ports {ft_data[9]}]
set_property PACKAGE_PIN W16  [get_ports {ft_data[10]}]
set_property PACKAGE_PIN W15  [get_ports {ft_data[11]}]
set_property PACKAGE_PIN AB17 [get_ports {ft_data[12]}]
set_property PACKAGE_PIN AB16 [get_ports {ft_data[13]}]
set_property PACKAGE_PIN V19  [get_ports {ft_data[14]}]
set_property PACKAGE_PIN V18  [get_ports {ft_data[15]}]
set_property PACKAGE_PIN G4   [get_ports {ft_data[16]}]
set_property PACKAGE_PIN H3   [get_ports {ft_data[17]}]
set_property PACKAGE_PIN G3   [get_ports {ft_data[18]}]
set_property PACKAGE_PIN P5   [get_ports {ft_data[19]}]
set_property PACKAGE_PIN P4   [get_ports {ft_data[20]}]
set_property PACKAGE_PIN P6   [get_ports {ft_data[21]}]
set_property PACKAGE_PIN N5   [get_ports {ft_data[22]}]
set_property PACKAGE_PIN M6   [get_ports {ft_data[23]}]
set_property PACKAGE_PIN M5   [get_ports {ft_data[24]}]
set_property PACKAGE_PIN L5   [get_ports {ft_data[25]}]
set_property PACKAGE_PIN L4   [get_ports {ft_data[26]}]
set_property PACKAGE_PIN K6   [get_ports {ft_data[27]}]
set_property PACKAGE_PIN J6   [get_ports {ft_data[28]}]
set_property PACKAGE_PIN E2   [get_ports {ft_data[29]}]
set_property PACKAGE_PIN D2   [get_ports {ft_data[30]}]
set_property PACKAGE_PIN M3   [get_ports {ft_data[31]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ft_data[*]}]

set_property SLEW FAST [get_ports {ft_data[*] ft_be[*] ft_oe ft_rd ft_wr}]
set_property DRIVE 8   [get_ports {ft_data[*] ft_be[*] ft_oe ft_rd ft_wr ft_reset ft_wakeup}]
