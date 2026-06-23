
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/06/2026 02:15:26 PM
// Design Name: 
// Module Name: neorv_ddr_top
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
//Date        : Sat Jun  6 12:06:39 2026
//Host        : gj-007 running 64-bit Ubuntu 24.04.4 LTS
//Command     : generate_target neorv_ddr_wrapper.bd
//Design      : neorv_ddr_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module neorv_ddr_wrapper
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
    clk_in1_0,
    gpio_i_0,
    gpio_o_0,
    jtag_tck_i_0,
    jtag_tdi_i_0,
    jtag_tdo_o_0,
    jtag_tms_i_0,
    pwm_o_0,
    resetn_0,
    spi_clk_o_0,
    spi_cs_0,
    spi_dat_i_0,
    spi_dat_o_0,
    twi_scl_io_0,
    twi_sda_io_0,
    uart0_rxd_i_0,
    uart0_txd_o_0);
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
  input clk_in1_0;
  input [0:0]gpio_i_0;
  output [4:0]gpio_o_0;
  input jtag_tck_i_0;
  input jtag_tdi_i_0;
  output jtag_tdo_o_0;
  input jtag_tms_i_0;
  output [0:0]pwm_o_0;
  input resetn_0;
  output spi_clk_o_0;
  output [2:0]spi_cs_0;
  input spi_dat_i_0;
  output spi_dat_o_0;
  inout twi_scl_io_0;
  inout twi_sda_io_0;
  input uart0_rxd_i_0;
  output uart0_txd_o_0;

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
  wire clk_in1_0;
  wire [0:0]gpio_i_0;
  wire [4:0]gpio_o_0;
  wire jtag_tck_i_0;
  wire jtag_tdi_i_0;
  wire jtag_tdo_o_0;
  wire jtag_tms_i_0;
  wire [0:0]pwm_o_0;
  wire resetn_0;
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

  neorv_ddr neorv_ddr_i
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
        .clk_in1_0(clk_in1_0),
        .gpio_i_0(gpio_i_0),
        .gpio_o_0(gpio_o_0),
        .jtag_tck_i_0(jtag_tck_i_0),
        .jtag_tdi_i_0(jtag_tdi_i_0),
        .jtag_tdo_o_0(jtag_tdo_o_0),
        .jtag_tms_i_0(jtag_tms_i_0),
        .pwm_o_0(pwm_o_0),
        .resetn_0(resetn_0),
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



module neorv_ddr_top(

    );
endmodule
