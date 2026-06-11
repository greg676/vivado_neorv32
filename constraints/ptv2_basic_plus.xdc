# ── neorv_basic_plus.xdc ───────────────────────────────────────
# Pinout & timing constraints for neorv_basic_plus block design
#
# Clock tree (Vivado-generated names from clk_wiz IPs):
#   clk (W19, 100 MHz) → clk_wiz_0 / clk_wiz_1 cascade
#     clk_out1_neorv_basic_plus_clk_wiz_0_0_1  = 160 MHz  (system)
#     clk_out2_neorv_basic_plus_clk_wiz_0_0_1  = 100 MHz  (cascade feed)
#     clk_out1_neorv_basic_plus_clk_wiz_1_0_1  = 12.288 MHz (audio)
#
# CDC: 160 MHz system ↔ 12.288 MHz audio are independent cascaded MMCMs.
# sd_in_codec uses 2-FF toggle synchronizers on wr_ready/rd_done.
# No data-path signals cross domains — false paths below tell Vivado
# not to analyze setup/hold on these architecturally-correct crossings.

# ── Voltage ──────────────────────────────────────────────────────
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# ── Primary Clock ─────────────────────────────────────────────────
# Board oscillator 100 MHz → clk_wiz_0 clk_in1.
# clk_wiz auto-XDC already creates clock on clk_in1 port.
# We define the port location/IOSTANDARD here; the period comes from clk_wiz OOC XDC.
# Redundant create_clock here helps Vivado resolve the clock tree earlier.
set_property IOSTANDARD LVCMOS33 [get_ports clk]
set_property PACKAGE_PIN W19 [get_ports clk]
create_clock -period 10.000 -name clk_100mhz -waveform {0.000 5.000} [get_ports clk]
set_input_jitter [get_clocks clk_100mhz] 0.100

# ── Reset ────────────────────────────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports resetn]
set_property PACKAGE_PIN N15 [get_ports resetn]

set_property IOSTANDARD LVCMOS33 [get_ports aux_reset_in_0]
set_property PACKAGE_PIN A15 [get_ports aux_reset_in_0]
set_property PULLTYPE PULLUP [get_ports aux_reset_in_0]

# ── JTAG ─────────────────────────────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tck_i]
set_property PACKAGE_PIN Y3 [get_ports jtag_tck_i]

set_property IOSTANDARD LVCMOS33 [get_ports jtag_tdi_i]
set_property PACKAGE_PIN AA3 [get_ports jtag_tdi_i]

set_property IOSTANDARD LVCMOS33 [get_ports jtag_tdo_o]
set_property PACKAGE_PIN AA1 [get_ports jtag_tdo_o]

set_property IOSTANDARD LVCMOS33 [get_ports jtag_tms_i]
set_property PACKAGE_PIN AB1 [get_ports jtag_tms_i]

# ── UART0 (debug console via RP2040) ─────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports uart0_rxd_i]
set_property PACKAGE_PIN F19 [get_ports uart0_rxd_i]

set_property IOSTANDARD LVCMOS33 [get_ports uart0_txd_o]
set_property PACKAGE_PIN B15 [get_ports uart0_txd_o]

# ── I²C (CS42448 @ 0x48 + Si5351A @ 0x60) ────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports twi_scl_io_0]
set_property PACKAGE_PIN B20 [get_ports twi_scl_io_0]
set_property PULLTYPE PULLUP [get_ports twi_scl_io_0]

set_property IOSTANDARD LVCMOS33 [get_ports twi_sda_io_0]
set_property PACKAGE_PIN C14 [get_ports twi_sda_io_0]
set_property PULLTYPE PULLUP [get_ports twi_sda_io_0]

# ── Audio TDM ────────────────────────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports LRCLK_0]
set_property PACKAGE_PIN G21 [get_ports LRCLK_0]

set_property IOSTANDARD LVCMOS33 [get_ports SCLK_0]
set_property PACKAGE_PIN G22 [get_ports SCLK_0]

set_property IOSTANDARD LVCMOS33 [get_ports sdin_0]
set_property PACKAGE_PIN E18 [get_ports sdin_0]

# ── SPI (Display, Touch, SD Card) ────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports spi_clk_o_0]
set_property PACKAGE_PIN W4 [get_ports spi_clk_o_0]

set_property IOSTANDARD LVCMOS33 [get_ports spi_dat_i_0]
set_property PACKAGE_PIN V4 [get_ports spi_dat_i_0]

set_property IOSTANDARD LVCMOS33 [get_ports spi_dat_o_0]
set_property PACKAGE_PIN AA4 [get_ports spi_dat_o_0]

# ── PWM ──────────────────────────────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports {pwm_o_0[0]}]
set_property PACKAGE_PIN T4 [get_ports {pwm_o_0[0]}]

# ── GPIO Input ───────────────────────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_i_0[0]}]
set_property PACKAGE_PIN R4 [get_ports {gpio_i_0[0]}]

# ── Dout_0 (GPIO outputs [2:0]) ───────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports {Dout_0[2]}]
set_property PACKAGE_PIN U6 [get_ports {Dout_0[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {Dout_0[1]}]
set_property PACKAGE_PIN V8 [get_ports {Dout_0[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {Dout_0[0]}]
set_property PACKAGE_PIN V9 [get_ports {Dout_0[0]}]

# ── Dout_1 (GPIO outputs [6:2]) ───────────────────────────────────
set_property IOSTANDARD LVCMOS33 [get_ports {Dout_1[4]}]
set_property PACKAGE_PIN U5 [get_ports {Dout_1[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {Dout_1[3]}]
set_property PACKAGE_PIN T5 [get_ports {Dout_1[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {Dout_1[2]}]
set_property PACKAGE_PIN D14 [get_ports {Dout_1[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {Dout_1[1]}]
set_property PACKAGE_PIN E14 [get_ports {Dout_1[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {Dout_1[0]}]
set_property PACKAGE_PIN E13 [get_ports {Dout_1[0]}]

# ── Clock Groups & CDC ───────────────────────────────────────────
# The three clock domains from two cascaded MMCMs:
#   GROUP_160M: clk_out1_neorv_basic_plus_clk_wiz_0_0_1  (160 MHz system)
#   GROUP_100M: clk_out2_neorv_basic_plus_clk_wiz_0_0_1  (100 MHz cascade)
#   GROUP_12M:  clk_out1_neorv_basic_plus_clk_wiz_1_0_1  (12.288 MHz audio)
#
# GROUP_100M and GROUP_12M are from the same clk_wiz_1 MMCM —
# Vivado auto-handles their relationship. GROUP_160M is from a
# different MMCM (clk_wiz_0) and is asynchronous to the audio domain.
#
# sd_in_codec_master_s handles the 160 MHz → 12.288 MHz CDC with
# 2-FF toggle synchronizers on wr_ready / rd_done. No data-path
# signals cross — only toggles, which are architecturally false paths.

# Group the system clock (and its generated clocks) against the
# audio clock (and its generated clocks). The audio clock is derived
# from clk_wiz_1, which is cascaded from clk_wiz_0. Vivado doesn't
# auto-group cascaded MMCM outputs as async, so we do it explicitly.
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks clk_100mhz] \
  -group [get_clocks -include_generated_clocks \
    -of_objects [get_pins neorv_basic_plus_i/clk_wiz_1/inst/mmcm_adv_inst/CLKOUT0]]

# False paths for the CDC crossing between 160 MHz system and 12.288 MHz audio.
# These crossings are architecturally intentional and handled by synchronizers.
set_false_path \
  -from [get_clocks -include_generated_clocks clk_100mhz] \
  -to [get_clocks -include_generated_clocks \
    -of_objects [get_pins neorv_basic_plus_i/clk_wiz_1/inst/mmcm_adv_inst/CLKOUT0]]
set_false_path \
  -from [get_clocks -include_generated_clocks \
    -of_objects [get_pins neorv_basic_plus_i/clk_wiz_1/inst/mmcm_adv_inst/CLKOUT0]] \
  -to [get_clocks -include_generated_clocks clk_100mhz]
