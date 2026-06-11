`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/10/2026 05:55:58 PM
// Design Name: 
// Module Name: neorv_basic_plus_top
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
//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
//Date        : Wed Jun 10 17:54:08 2026
//Host        : gj-007 running 64-bit Ubuntu 24.04.4 LTS
//Command     : generate_target neorv_basic_plus_wrapper.bd
//Design      : neorv_basic_plus_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module neorv_basic_plus_top
   (Dout_0,
    Dout_1,
    LRCLK_0,
    SCLK_0,
    aux_reset_in_0,
    clk,
    gpio_i_0,
    jtag_tck_i,
    jtag_tdi_i,
    jtag_tdo_o,
    jtag_tms_i,
    pwm_o_0,
    resetn,
    sdin_0,
    spi_clk_o_0,
    spi_dat_i_0,
    spi_dat_o_0,
    twi_scl_io_0,
    twi_sda_io_0,
    uart0_rxd_i,
    uart0_txd_o);
  output [2:0]Dout_0;
  output [4:0]Dout_1;
  output LRCLK_0;
  output SCLK_0;
  input aux_reset_in_0;
  input clk;
  input [0:0]gpio_i_0;
  input jtag_tck_i;
  input jtag_tdi_i;
  output jtag_tdo_o;
  input jtag_tms_i;
  output [0:0]pwm_o_0;
  input resetn;
  input sdin_0;
  output spi_clk_o_0;
  input spi_dat_i_0;
  output spi_dat_o_0;
  inout twi_scl_io_0;
  inout twi_sda_io_0;
  input uart0_rxd_i;
  output uart0_txd_o;

  wire [2:0]Dout_0;
  wire [4:0]Dout_1;
  wire LRCLK_0;
  wire SCLK_0;
  wire aux_reset_in_0;
  wire clk;
  wire [0:0]gpio_i_0;
  wire jtag_tck_i;
  wire jtag_tdi_i;
  wire jtag_tdo_o;
  wire jtag_tms_i;
  wire [0:0]pwm_o_0;
  wire resetn;
  wire sdin_0;
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

  neorv_basic_plus neorv_basic_plus_i
       (.Dout_0(Dout_0),
        .Dout_1(Dout_1),
        .LRCLK_0(LRCLK_0),
        .SCLK_0(SCLK_0),
        .aux_reset_in_0(aux_reset_in_0),
        .clk(clk),
        .gpio_i_0(gpio_i_0),
        .jtag_tck_i(jtag_tck_i),
        .jtag_tdi_i(jtag_tdi_i),
        .jtag_tdo_o(jtag_tdo_o),
        .jtag_tms_i(jtag_tms_i),
        .pwm_o_0(pwm_o_0),
        .resetn(resetn),
        .sdin_0(sdin_0),
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



