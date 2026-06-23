# Global configuration
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

set_property IOSTANDARD LVCMOS33 [get_ports clk_in1_0]
set_property IOSTANDARD LVCMOS33 [get_ports resetn_0]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_i_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_o_0[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_o_0[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_o_0[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_o_0[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gpio_o_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pwm_o_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tck_i_0]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tdi_i_0]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tdo_o_0]
set_property IOSTANDARD LVCMOS33 [get_ports jtag_tms_i_0]
set_property IOSTANDARD LVCMOS33 [get_ports uart0_rxd_i_0]
set_property IOSTANDARD LVCMOS33 [get_ports uart0_txd_o_0]
set_property IOSTANDARD LVCMOS33 [get_ports twi_scl_io_0]
set_property IOSTANDARD LVCMOS33 [get_ports twi_sda_io_0]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_cs_0[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_cs_0[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {spi_cs_0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports spi_clk_o_0]
set_property IOSTANDARD LVCMOS33 [get_ports spi_dat_i_0]
set_property IOSTANDARD LVCMOS33 [get_ports spi_dat_o_0]
set_property IOSTANDARD LVCMOS33 [get_ports sdin_0]
set_property IOSTANDARD LVCMOS33 [get_ports ext_resetn_in_0]
set_property IOSTANDARD LVCMOS33 [get_ports LRCLK]
set_property IOSTANDARD LVCMOS33 [get_ports SCLK]
set_property PULLTYPE PULLUP [get_ports ext_resetn_in_0]
set_property PULLTYPE PULLUP [get_ports twi_scl_io_0]
set_property PULLTYPE PULLUP [get_ports twi_sda_io_0]

set_property PACKAGE_PIN W19 [get_ports clk_in1_0]
set_property PACKAGE_PIN N15 [get_ports resetn_0]
set_property PACKAGE_PIN R4 [get_ports {gpio_i_0[0]}]
set_property PACKAGE_PIN U5 [get_ports {gpio_o_0[4]}]
set_property PACKAGE_PIN T5 [get_ports {gpio_o_0[3]}]
set_property PACKAGE_PIN D14 [get_ports {gpio_o_0[2]}]
set_property PACKAGE_PIN E14 [get_ports {gpio_o_0[1]}]
set_property PACKAGE_PIN E13 [get_ports {gpio_o_0[0]}]
set_property PACKAGE_PIN T4 [get_ports {pwm_o_0[0]}]
set_property PACKAGE_PIN Y3 [get_ports jtag_tck_i_0]
set_property PACKAGE_PIN AA3 [get_ports jtag_tdi_i_0]
set_property PACKAGE_PIN AA1 [get_ports jtag_tdo_o_0]
set_property PACKAGE_PIN AB1 [get_ports jtag_tms_i_0]
set_property PACKAGE_PIN F19 [get_ports uart0_rxd_i_0]
set_property PACKAGE_PIN B15 [get_ports uart0_txd_o_0]
set_property PACKAGE_PIN B20 [get_ports twi_scl_io_0]
set_property PACKAGE_PIN C14 [get_ports twi_sda_io_0]
set_property PACKAGE_PIN U6 [get_ports {spi_cs_0[2]}]
set_property PACKAGE_PIN V8 [get_ports {spi_cs_0[1]}]
set_property PACKAGE_PIN V9 [get_ports {spi_cs_0[0]}]
set_property PACKAGE_PIN W4 [get_ports spi_clk_o_0]
set_property PACKAGE_PIN V4 [get_ports spi_dat_i_0]
set_property PACKAGE_PIN AA4 [get_ports spi_dat_o_0]
set_property PACKAGE_PIN E18 [get_ports sdin_0]
set_property PACKAGE_PIN A15 [get_ports ext_resetn_in_0]
set_property PACKAGE_PIN G21 [get_ports LRCLK]
set_property PACKAGE_PIN G22 [get_ports SCLK]

# ---------------------------------------------------------------------------
# Clock constraints
# ---------------------------------------------------------------------------
# Clock tree:
#   clk_in1_0 (100MHz onboard osc, pin W19)
#     -> clk_wiz_0: MMCM 100MHz in -> clk_out1 (100MHz system) + clk_out2 (100MHz feed)
#       -> clk_wiz_1: MMCM 100MHz in -> clk_out1 (12.288MHz audio MCLK)
#
# Generated clock names (from clk_wiz auto-XDC):
#   clk_out1_neorv_noddr_clk_wiz_0_0   = 100.000 MHz system domain
#   clk_out1_neorv_noddr_clk_wiz_1_0_1 =  12.288 MHz audio codec domain

# ---------------------------------------------------------------------------
# Asynchronous clock groups
# ---------------------------------------------------------------------------
# The 12.288MHz audio domain (clk_wiz_1) and 100MHz system domain (clk_wiz_0)
# are independent — no guaranteed phase relationship between cascaded MMCMs.
# CDC is handled inside sd_in_codec_master_s_0 via 2-FF synchronizers on
# wr_ready/rd_done toggle flags. No data-path signals cross clock domains.
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks clk_in1_0] -group [get_clocks -include_generated_clocks -of_objects [get_pins neorv_noddr_i/clk_wiz_1/inst/mmcm_adv_inst/CLKOUT0]]

# False paths: all crossings between audio and system clock domains.
# These are architecturally correct — the sd_in module synchronizes toggles,
# not data. Vivado should not attempt setup/hold between these domains.
set_false_path -from [get_clocks clk_out1_neorv_noddr_clk_wiz_1_0_1] -to [get_clocks clk_out1_neorv_noddr_clk_wiz_0_0]
set_false_path -from [get_clocks clk_out1_neorv_noddr_clk_wiz_0_0] -to [get_clocks clk_out1_neorv_noddr_clk_wiz_1_0_1]

# Suppress TIMING-2 + TIMING-4: clk_wiz_1 auto-XDC creates a primary clock on
# its internal clk_in1 pin, but that net is already driven by clk_wiz_0.clk_out2.
# The async groups above handle the CDC correctly.




