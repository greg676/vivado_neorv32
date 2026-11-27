# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# OPTIONAL Br BOTTOM Bank A 8-channel probe pinout (FPGA bank 16, LVCMOS33).
# Off by default: probe_i is the instrument — the user wires it in the BD.
# Enable GUI C_INCLUDE_BR_XDC only when probe_i is made external with these
# names. Do not use with a custom LA input board. Pt only (not Au).
#
#   ch  Br pin   FPGA   bank
#   0   A33      B13    16
#   1   A34      A14    16
#   2   A35      C13    16
#   3   A36      A13    16
#   4   A39      C17    16     MRCC N
#   5   A40      B18    16     SRCC N
#   6   A41      D17    16     MRCC P
#   7   A42      B17    16     SRCC P

set_property PACKAGE_PIN B13 [get_ports {probe_i[0]}]
set_property PACKAGE_PIN A14 [get_ports {probe_i[1]}]
set_property PACKAGE_PIN C13 [get_ports {probe_i[2]}]
set_property PACKAGE_PIN A13 [get_ports {probe_i[3]}]
set_property PACKAGE_PIN C17 [get_ports {probe_i[4]}]
set_property PACKAGE_PIN B18 [get_ports {probe_i[5]}]
set_property PACKAGE_PIN D17 [get_ports {probe_i[6]}]
set_property PACKAGE_PIN B17 [get_ports {probe_i[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {probe_i[*]}]
set_false_path -from [get_ports {probe_i[*]}]
