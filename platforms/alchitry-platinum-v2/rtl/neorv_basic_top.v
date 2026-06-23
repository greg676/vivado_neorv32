`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/09/2026 01:01:26 PM
// Design Name: 
// Module Name: neorv_basic_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module neorv_basic_top
   (Dout_0,
    LRCLK_0,
    SCLK_0,
    clk,
    gpio_i_0,
    gpio_o_0,
    jtag_tck_i,
    jtag_tdi_i,
    jtag_tdo_o,
    jtag_tms_i,
    pwm_o_0,
    resetn,
    spi_clk_o_0,
    spi_dat_i_0,
    spi_dat_o_0,
    twi_scl_io_0,
    twi_sda_io_0,
    uart0_rxd_i,
    uart0_txd_o);
  output [2:0]Dout_0;
  output LRCLK_0;
  output SCLK_0;
  input clk;
  input [0:0]gpio_i_0;
  output [4:0]gpio_o_0;
  input jtag_tck_i;
  input jtag_tdi_i;
  output jtag_tdo_o;
  input jtag_tms_i;
  output [0:0]pwm_o_0;
  input resetn;
  output spi_clk_o_0;
  input spi_dat_i_0;
  output spi_dat_o_0;
  inout twi_scl_io_0;
  inout twi_sda_io_0;
  input uart0_rxd_i;
  output uart0_txd_o;
  
  wire [2:0]Dout_0;
  wire LRCLK_0;
  wire SCLK_0;
  wire clk;
  wire [0:0]gpio_i_0;
  wire [4:0]gpio_o_0;
  wire jtag_tck_i;
  wire jtag_tdi_i;
  wire jtag_tdo_o;
  wire jtag_tms_i;
  wire [0:0]pwm_o_0;
  wire resetn;
  wire spi_clk_o_0;
  wire spi_dat_i_0;
  wire spi_dat_o_0;
  wire twi_scl_i_0;
  wire twi_scl_o_0;
  wire twi_sda_i_0;
  wire twi_sda_o_0;
  wire uart0_rxd_i;
  wire uart0_txd_o;
  wire twi_sda_io_0;
  wire twi_scl_io_0;
  
  IOBUF twi_sda_io_iobuf
       (.I(1'b0),
        .IO(twi_sda_io_0),
        .O(twi_sda_i_0),
        .T(twi_sda_o_0));
  IOBUF twi_scl_io_iobuf
       (.I(1'b0),
        .IO(twi_scl_io_0),
        .O(twi_scl_i_0),
        .T(twi_scl_o_0));
  neorv_basic neorv_basic_i
       (.Dout_0(Dout_0),
        .LRCLK_0(LRCLK_0),
        .SCLK_0(SCLK_0),
        .clk(clk),
        .gpio_i_0(gpio_i_0),
        .gpio_o_0(gpio_o_0),
        .jtag_tck_i(jtag_tck_i),
        .jtag_tdi_i(jtag_tdi_i),
        .jtag_tdo_o(jtag_tdo_o),
        .jtag_tms_i(jtag_tms_i),
        .pwm_o_0(pwm_o_0),
        .resetn(resetn),
        .spi_clk_o_0(spi_clk_o_0),
        .spi_dat_i_0(spi_dat_i_0),
        .spi_dat_o_0(spi_dat_o_0),
        .twi_scl_i_0(twi_scl_i_0),
        .twi_scl_o_0(twi_scl_o_0),
        .twi_sda_i_0(twi_sda_i_0),
        .twi_sda_o_0(twi_sda_o_0),
        .uart0_rxd_i(uart0_rxd_i),
        .uart0_txd_o(uart0_txd_o));
endmodule



