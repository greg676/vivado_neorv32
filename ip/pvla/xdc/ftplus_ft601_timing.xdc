# PVLA IP-scoped FT601 I/O timing. Included when C_PHY=FT601.
# Numbers match platforms/.../ptv2_ft601_loopback.xdc (PR #5 timing close).

# Board clk (if present at the wrapper) is independent of ft_clk.
set_clock_groups -asynchronous -quiet \
    -group [get_clocks -quiet -include_generated_clocks clk] \
    -group [get_clocks -quiet -include_generated_clocks ft_clk]

# DS_FT600Q-FT601Q AC + ~0.4 ns Ft+ connector.
set_input_delay  -clock [get_clocks ft_clk] -max 7.400 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
set_input_delay  -clock [get_clocks ft_clk] -min 0.600 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
set_output_delay -clock [get_clocks ft_clk] -max 1.400 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]
set_output_delay -clock [get_clocks ft_clk] -min -0.100 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]

set_false_path -to [get_ports ft_reset]
set_false_path -to [get_ports ft_wakeup]
set_false_path -from [get_ports rst_n] -quiet
set_false_path -from [get_ports probe_i*] -quiet
