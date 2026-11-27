# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# PVLA IP-scoped FT601 I/O timing. Included when C_PHY=FT601.
# Output max 0.90 ns is the PR #18 packed-IOB budget (Lucid DATA-before-WR).
# Not the old 1.4 ns number that missed WNS on Au+Ft+.

# Board clk (if present at the wrapper) is independent of ft_clk.
set_clock_groups -asynchronous -quiet \
    -group [get_clocks -quiet -include_generated_clocks clk] \
    -group [get_clocks -quiet -include_generated_clocks ft_clk]

# DS_FT600Q-FT601Q AC + ~0.4 ns Ft+ connector.
set_input_delay  -clock [get_clocks ft_clk] -max 7.400 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
set_input_delay  -clock [get_clocks ft_clk] -min 0.600 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
set_output_delay -clock [get_clocks ft_clk] -max 0.900 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]
set_output_delay -clock [get_clocks ft_clk] -min -0.100 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]

set_false_path -to [get_ports ft_reset]
set_false_path -to [get_ports ft_wakeup]
set_false_path -from [get_ports rst_n] -quiet
set_false_path -from [get_ports probe_i*] -quiet
