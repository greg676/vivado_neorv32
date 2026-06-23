//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/07/2026 07:37:42 AM
// Design Name: 
// Module Name: neorv_noddr_top
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
//Date        : Sun Jun  7 07:35:56 2026
//Host        : gj-007 running 64-bit Ubuntu 24.04.4 LTS
//Command     : generate_target neorv_noddr_wrapper.bd
//Design      : neorv_noddr_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module neorv_noddr_top
   (LRCLK,
    SCLK,
    clk_in1_0,
    ext_resetn_in_0,
    gpio_i_0,
    gpio_o_0,
    jtag_tck_i_0,
    jtag_tdi_i_0,
    jtag_tdo_o_0,
    jtag_tms_i_0,
    pwm_o_0,
    resetn_0,
    sdin_0,
    spi_clk_o_0,
    spi_cs_0,
    spi_dat_i_0,
    spi_dat_o_0,
    twi_scl_io_0,
    twi_sda_io_0,
    uart0_rxd_i_0,
    uart0_txd_o_0);
  output LRCLK;
  output SCLK;
  input clk_in1_0;
  input ext_resetn_in_0;
  input [0:0]gpio_i_0;
  output [4:0]gpio_o_0;
  input jtag_tck_i_0;
  input jtag_tdi_i_0;
  output jtag_tdo_o_0;
  input jtag_tms_i_0;
  output [0:0]pwm_o_0;
  input resetn_0;
  input sdin_0;
  output spi_clk_o_0;
  output [2:0]spi_cs_0;
  input spi_dat_i_0;
  output spi_dat_o_0;
  inout twi_scl_io_0;
  inout twi_sda_io_0;
  input uart0_rxd_i_0;
  output uart0_txd_o_0;

  wire LRCLK;
  wire SCLK;
  wire clk_in1_0;
  wire ext_resetn_in_0;
  wire [0:0]gpio_i_0;
  wire [4:0]gpio_o_0;
  wire jtag_tck_i_0;
  wire jtag_tdi_i_0;
  wire jtag_tdo_o_0;
  wire jtag_tms_i_0;
  wire [0:0]pwm_o_0;
  wire resetn_0;
  wire sdin_0;
  wire spi_clk_o_0;
  wire [2:0]spi_cs_0;
  wire spi_dat_i_0;
  wire spi_dat_o_0;
  wire twi_scl_i_0;
  wire twi_scl_o_0;
  wire twi_sda_i_0;
  wire twi_sda_o_0;
  wire uart0_rxd_i_0;
  wire uart0_txd_o_0;
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

  neorv_noddr neorv_noddr_i
       (.LRCLK(LRCLK),
        .SCLK(SCLK),
        .clk_in1_0(clk_in1_0),
        .ext_resetn_in_0(ext_resetn_in_0),
        .gpio_i_0(gpio_i_0),
        .gpio_o_0(gpio_o_0),
        .jtag_tck_i_0(jtag_tck_i_0),
        .jtag_tdi_i_0(jtag_tdi_i_0),
        .jtag_tdo_o_0(jtag_tdo_o_0),
        .jtag_tms_i_0(jtag_tms_i_0),
        .pwm_o_0(pwm_o_0),
        .resetn_0(resetn_0),
        .sdin_0(sdin_0),
        .spi_clk_o_0(spi_clk_o_0),
        .spi_cs_0(spi_cs_0),
        .spi_dat_i_0(spi_dat_i_0),
        .spi_dat_o_0(spi_dat_o_0),
        .twi_scl_i_0(twi_scl_i_0),
        .twi_scl_o_0(twi_scl_o_0),
        .twi_sda_i_0(twi_sda_i_0),
        .twi_sda_o_0(twi_sda_o_0),
        .uart0_rxd_i_0(uart0_rxd_i_0),
        .uart0_txd_o_0(uart0_txd_o_0));
endmodule



