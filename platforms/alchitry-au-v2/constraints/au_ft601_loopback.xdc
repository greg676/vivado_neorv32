# Common constraints: Alchitry Au V2 board clock/reset/LEDs + FT601 timing.
# Pair with constraints/au_ft601_pins_v2.xdc (published Ft+ V2).
# Board oscillator / LED / rst pins from au_base.xdc.

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR NO [current_design]

# ── Board oscillator 100 MHz (reset sequencer / LED heartbeat) ──
set_property PACKAGE_PIN N14 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name clk_100mhz -waveform {0.000 5.000} [get_ports clk]
set_input_jitter [get_clocks clk_100mhz] 0.100

# ── Reset button (active low) ───────────────────────────────────
set_property PACKAGE_PIN P6 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ── User LEDs ───────────────────────────────────────────────────
set_property PACKAGE_PIN K13 [get_ports {led[0]}]
set_property PACKAGE_PIN K12 [get_ports {led[1]}]
set_property PACKAGE_PIN L14 [get_ports {led[2]}]
set_property PACKAGE_PIN L13 [get_ports {led[3]}]
set_property PACKAGE_PIN M15 [get_ports {led[4]}]
set_property PACKAGE_PIN M14 [get_ports {led[5]}]
set_property PACKAGE_PIN M12 [get_ports {led[6]}]
set_property PACKAGE_PIN P14 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_100mhz] \
    -group [get_clocks -include_generated_clocks ft_clk]

# DS_FT600Q-FT601Q AC + ~0.4 ns Ft+ connector (same numbers as Pt loopback).
set_input_delay  -clock [get_clocks ft_clk] -max 7.400 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
set_input_delay  -clock [get_clocks ft_clk] -min 0.600 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
# IOB FF + OBUF Tco (~3.7 ns) plus BUFG insertion (~5.3 ns) cannot close the
# previous 1.4 ns max (DS tSU + 0.4 ns connector) at slow corner (WNS −0.4).
# 0.90 ns is the leftover budget with IOB packing; FT601 still sees DATA a
# full ft_clk before WR (Lucid combo + IOB).
set_output_delay -clock [get_clocks ft_clk] -max 0.900 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]
set_output_delay -clock [get_clocks ft_clk] -min -0.100 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]

set_property SLEW FAST [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]
set_property DRIVE 8 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]

set_false_path -to [get_ports ft_reset]
set_false_path -to [get_ports ft_wakeup]
set_false_path -from [get_ports rst_n]
