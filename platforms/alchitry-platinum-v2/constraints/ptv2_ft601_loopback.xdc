# ── ptv2_ft601_loopback.xdc ─────────────────────────────────────
# Common constraints for the dedicated FT601 loopback top on
# Alchitry Pt V2 + Ft+ (top) + Br (bottom).
#
# Pair with ONE of:
#   constraints/ptv2_ft601_pins_pt_alpha.xdc   (first-batch Pt, default)
#   constraints/ptv2_ft601_pins_v2.xdc         (production Pt V2)
#
# Analyzer inputs are comments only — do not implement the sampler here.

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]

# ── Board oscillator 100 MHz (reset sequencer / LED heartbeat) ──
set_property PACKAGE_PIN W19 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name clk_100mhz -waveform {0.000 5.000} [get_ports clk]
set_input_jitter [get_clocks clk_100mhz] 0.100

# ── Reset button (active low) ───────────────────────────────────
set_property PACKAGE_PIN N15 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ── User LEDs ───────────────────────────────────────────────────
set_property PACKAGE_PIN P19 [get_ports {led[0]}]
set_property PACKAGE_PIN P20 [get_ports {led[1]}]
set_property PACKAGE_PIN T21 [get_ports {led[2]}]
set_property PACKAGE_PIN R19 [get_ports {led[3]}]
set_property PACKAGE_PIN V22 [get_ports {led[4]}]
set_property PACKAGE_PIN U21 [get_ports {led[5]}]
set_property PACKAGE_PIN T20 [get_ports {led[6]}]
set_property PACKAGE_PIN W20 [get_ports {led[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# ── FT601 clock (100 MHz from Ft+) ──────────────────────────────
# Package pin is in the pin-map XDC (same on PT_ALPHA and V2: H4).
# Period is defined there together with the pin.

# Board clk and FT601 clk are independent.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_100mhz] \
    -group [get_clocks -include_generated_clocks ft_clk]

# ── I/O timing vs ft_clk (FT601 245 sync FIFO, 100 MHz) ─────────
# Conservative pad delays; IOB FFs are required in the RTL.
set_input_delay  -clock [get_clocks ft_clk] -max 7.000 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
set_input_delay  -clock [get_clocks ft_clk] -min 1.000 [get_ports {ft_data[*] ft_be[*] ft_rxf ft_txe}]
set_output_delay -clock [get_clocks ft_clk] -max 2.000 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]
set_output_delay -clock [get_clocks ft_clk] -min 0.000 [get_ports {ft_oe ft_rd ft_wr ft_data[*] ft_be[*]}]

# Reset/wakeup are DC from the board-clock sequencer.
set_false_path -to [get_ports ft_reset]
set_false_path -to [get_ports ft_wakeup]
set_false_path -from [get_ports rst_n]

# ── Reserved: 8 × LVCMOS33 analyzer inputs on Br BOTTOM Bank A ─
# Document only. These ports are NOT in ft601_loopback_top.
# All eight sit on FPGA bank 16, VCCO = 3.3 V (not the MV Bank B pins).
# Adjacent MRCC/SRCC pair A41/A42 is reserved as a future sample clock.
#
#   ch  Br pin   FPGA   bank  IOSTANDARD   notes
#   0   A33      B13    16    LVCMOS33
#   1   A34      A14    16    LVCMOS33
#   2   A35      C13    16    LVCMOS33
#   3   A36      A13    16    LVCMOS33
#   4   A39      C17    16    LVCMOS33     MRCC N
#   5   A40      B18    16    LVCMOS33     SRCC N
#   6   A41      D17    16    LVCMOS33     MRCC P  (future capture clock)
#   7   A42      B17    16    LVCMOS33     SRCC P
#
# set_property PACKAGE_PIN B13 [get_ports {la_in[0]}]
# set_property PACKAGE_PIN A14 [get_ports {la_in[1]}]
# set_property PACKAGE_PIN C13 [get_ports {la_in[2]}]
# set_property PACKAGE_PIN A13 [get_ports {la_in[3]}]
# set_property PACKAGE_PIN C17 [get_ports {la_in[4]}]
# set_property PACKAGE_PIN B18 [get_ports {la_in[5]}]
# set_property PACKAGE_PIN D17 [get_ports {la_in[6]}]
# set_property PACKAGE_PIN B17 [get_ports {la_in[7]}]
# set_property IOSTANDARD LVCMOS33 [get_ports {la_in[*]}]
