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
//Date        : Thu Jun 18 04:23:28 2026
//Host        : gj-007 running 64-bit Ubuntu 24.04.4 LTS
//Command     : generate_target neorv_basic_plus_wrapper.bd
//Design      : neorv_basic_plus_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module neorv_basic_plus_top

   (DDR3_0_addr,
    DDR3_0_ba,
    DDR3_0_cas_n,
    DDR3_0_ck_n,
    DDR3_0_ck_p,
    DDR3_0_cke,
    DDR3_0_cs_n,
    DDR3_0_dm,
    DDR3_0_dq,
    DDR3_0_dqs_n,
    DDR3_0_dqs_p,
    DDR3_0_odt,
    DDR3_0_ras_n,
    DDR3_0_reset_n,
    DDR3_0_we_n,
    LRCLK,
    MCLK,
    SCLK,
    alchitry_rxd_i,
    alchitry_txd_o,
    clk,
    ext_resetn,
    gpio_o,
    int_in,
    jtag_tck_i,
    jtag_tdi_i,
    jtag_tdo_o,
    jtag_tms_i,
    led0_o,
    led_pwm,
    resetn,
    spi_clk_o,
    spi_cs,
    spi_dat_i,
    spi_dat_o,
    twi_scl_io,
    twi_sda_io,
    uart0_rxd_i,
    uart0_txd_o);
  output [13:0]DDR3_0_addr;
  output [2:0]DDR3_0_ba;
  output DDR3_0_cas_n;
  output [0:0]DDR3_0_ck_n;
  output [0:0]DDR3_0_ck_p;
  output [0:0]DDR3_0_cke;
  output [0:0]DDR3_0_cs_n;
  output [1:0]DDR3_0_dm;
  inout [15:0]DDR3_0_dq;
  inout [1:0]DDR3_0_dqs_n;
  inout [1:0]DDR3_0_dqs_p;
  output [0:0]DDR3_0_odt;
  output DDR3_0_ras_n;
  output DDR3_0_reset_n;
  output DDR3_0_we_n;
  output LRCLK;
  output MCLK;
  output SCLK;
  input alchitry_rxd_i;
  output alchitry_txd_o;
  input clk;
  input ext_resetn;
  output [4:0]gpio_o;
  input [0:0]int_in;
  input jtag_tck_i;
  input jtag_tdi_i;
  output jtag_tdo_o;
  input jtag_tms_i;
  output [0:0]led0_o;
  output [0:0]led_pwm;
  input resetn;
  output spi_clk_o;
  output [3:0]spi_cs;
  input spi_dat_i;
  output spi_dat_o;
  inout twi_scl_io;
  inout twi_sda_io;
  input uart0_rxd_i;
  output uart0_txd_o;

  wire [13:0]DDR3_0_addr;
  wire [2:0]DDR3_0_ba;
  wire DDR3_0_cas_n;
  wire [0:0]DDR3_0_ck_n;
  wire [0:0]DDR3_0_ck_p;
  wire [0:0]DDR3_0_cke;
  wire [0:0]DDR3_0_cs_n;
  wire [1:0]DDR3_0_dm;
  wire [15:0]DDR3_0_dq;
  wire [1:0]DDR3_0_dqs_n;
  wire [1:0]DDR3_0_dqs_p;
  wire [0:0]DDR3_0_odt;
  wire DDR3_0_ras_n;
  wire DDR3_0_reset_n;
  wire DDR3_0_we_n;
  wire LRCLK;
  wire MCLK;
  wire SCLK;
  wire alchitry_rxd_i;
  wire alchitry_txd_o;
  wire clk;
  wire ext_resetn;
  wire [4:0]gpio_o;
  wire [0:0]int_in;
  wire jtag_tck_i;
  wire jtag_tdi_i;
  wire jtag_tdo_o;
  wire jtag_tms_i;
  wire [0:0]led0_o;
  wire [0:0]led_pwm;
  wire resetn;
  wire spi_clk_o;
  wire [3:0]spi_cs;
  wire spi_dat_i;
  wire spi_dat_o;
  wire twi_scl_i;
  wire twi_scl_o;
  wire twi_sda_i;
  wire twi_sda_o;
  wire uart0_rxd_i;
  wire uart0_txd_o;
  wire twi_scl_io;
  wire twi_sda_io;
  
  IOBUF twi_sda_io_iobuf
       (.I(1'b0),
        .IO(twi_sda_io),
        .O(twi_sda_i),
        .T(twi_sda_o));
  IOBUF twi_scl_io_iobuf
       (.I(1'b0),
        .IO(twi_scl_io),
        .O(twi_scl_i),
        .T(twi_scl_o));
  
  neorv_basic_plus neorv_basic_plus_i
       (.DDR3_0_addr(DDR3_0_addr),
        .DDR3_0_ba(DDR3_0_ba),
        .DDR3_0_cas_n(DDR3_0_cas_n),
        .DDR3_0_ck_n(DDR3_0_ck_n),
        .DDR3_0_ck_p(DDR3_0_ck_p),
        .DDR3_0_cke(DDR3_0_cke),
        .DDR3_0_cs_n(DDR3_0_cs_n),
        .DDR3_0_dm(DDR3_0_dm),
        .DDR3_0_dq(DDR3_0_dq),
        .DDR3_0_dqs_n(DDR3_0_dqs_n),
        .DDR3_0_dqs_p(DDR3_0_dqs_p),
        .DDR3_0_odt(DDR3_0_odt),
        .DDR3_0_ras_n(DDR3_0_ras_n),
        .DDR3_0_reset_n(DDR3_0_reset_n),
        .DDR3_0_we_n(DDR3_0_we_n),
        .LRCLK(LRCLK),
        .MCLK(MCLK),
        .SCLK(SCLK),
        .alchitry_rxd_i(alchitry_rxd_i),
        .alchitry_txd_o(alchitry_txd_o),
        .clk(clk),
        .ext_resetn(ext_resetn),
        .gpio_o(gpio_o),
        .int_in(int_in),
        .jtag_tck_i(jtag_tck_i),
        .jtag_tdi_i(jtag_tdi_i),
        .jtag_tdo_o(jtag_tdo_o),
        .jtag_tms_i(jtag_tms_i),
        .led0_o(led0_o),
        .led_pwm(led_pwm),
        .resetn(resetn),
        .spi_clk_o(spi_clk_o),
        .spi_cs(spi_cs),
        .spi_dat_i(spi_dat_i),
        .spi_dat_o(spi_dat_o),
        .twi_scl_i(twi_scl_i),
        .twi_scl_o(twi_scl_o),
        .twi_sda_i(twi_sda_i),
        .twi_sda_o(twi_sda_o),
        .uart0_rxd_i(uart0_rxd_i),
        .uart0_txd_o(uart0_txd_o));
endmodule

