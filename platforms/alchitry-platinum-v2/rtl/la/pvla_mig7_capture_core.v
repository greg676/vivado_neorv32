// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Pt-only PVLA capture: packed samples -> MIG7 256 MB AXI window ->
// dual 4 KiB BRAM ping-pong -> PR #18/#19 FT601 PHY (1024-word bursts).
//
// Does not replace the 4 KiB PHY. Sampler enable is DDR-side wr_ready
// (CDC FIFO), not TXE. Au has no DDR; this module is not used there.
// No NeoRV32. No QSPI.
module pvla_mig7_capture_core #(
    parameter [1:0]   SOURCE      = 2'd0,
    parameter integer DEPTH_WORDS = 2048,
    parameter [31:0]  BASE_ADDR   = 32'h2000_0000
) (
    input  wire         ft_clk,
    input  wire         rst_ft,

    input  wire         axi_clk,
    input  wire         axi_rst,
    input  wire         calib_done,

    inout  wire [31:0]  ft_data,
    inout  wire [3:0]   ft_be,
    input  wire         ft_rxf,
    input  wire         ft_txe,
    output wire         ft_oe,
    output wire         ft_rd,
    output wire         ft_wr,

    output wire [31:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,
    output wire [31:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    output wire         overflow_sticky,
    output wire         fifo_empty,
    output wire         tx_active,
    output wire [1:0]   source_sel,
    output wire [31:0]  ddr_used_words,
    output wire         calib_ok
);

    localparam integer BURST = 1024;

    wire [7:0]  s0, s1, s2, s3;
    wire [31:0] samp_word;
    wire        samp_ready;
    wire [31:0] wr_tdata;
    wire        wr_tvalid;
    wire        wr_tready;
    wire [31:0] rd_tdata;
    wire        rd_tvalid;
    wire        rd_tready;
    wire [31:0] pp_data;
    wire        pp_valid;
    wire        pp_ready;
    wire        dump_active;
    wire        ddr_ovf, pp_ovf;
    wire [31:0] rx_data;
    wire [3:0]  rx_be;
    wire        rx_valid;

    assign source_sel      = SOURCE;
    assign samp_word       = {s3, s2, s1, s0};
    assign fifo_empty      = ~pp_valid;
    assign tx_active       = dump_active;
    assign calib_ok        = calib_done;
    assign overflow_sticky = ddr_ovf | pp_ovf;

    la_pattern #(
        .SOURCE (SOURCE)
    ) u_pat (
        .clk    (ft_clk),
        .rst    (rst_ft),
        .enable (samp_ready),
        .s0     (s0),
        .s1     (s1),
        .s2     (s2),
        .s3     (s3)
    );

    la_dc_fwft #(
        .W     (32),
        .DEPTH (128)
    ) u_cdc_wr (
        .wr_clk   (ft_clk),
        .wr_rst   (rst_ft),
        .wr_data  (samp_word),
        .wr_valid (1'b1),
        .wr_ready (samp_ready),
        .rd_clk   (axi_clk),
        .rd_rst   (axi_rst),
        .rd_data  (wr_tdata),
        .rd_valid (wr_tvalid),
        .rd_ready (wr_tready)
    );

    la_ddr3_axi_buf #(
        .DEPTH_WORDS (DEPTH_WORDS),
        .BASE_ADDR   (BASE_ADDR)
    ) u_ddr (
        .axi_clk         (axi_clk),
        .axi_rst         (axi_rst),
        .calib_done      (calib_done),
        .s_tdata         (wr_tdata),
        .s_tvalid        (wr_tvalid),
        .s_tready        (wr_tready),
        .m_tdata         (rd_tdata),
        .m_tvalid        (rd_tvalid),
        .m_tready        (rd_tready),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready),
        .used_words      (ddr_used_words),
        .overflow_sticky (ddr_ovf)
    );

    wire [31:0] cdc_rd_data;
    wire        cdc_rd_valid;
    wire        pp_wr_ready;

    la_dc_fwft #(
        .W     (32),
        .DEPTH (128)
    ) u_cdc_rd (
        .wr_clk   (axi_clk),
        .wr_rst   (axi_rst),
        .wr_data  (rd_tdata),
        .wr_valid (rd_tvalid),
        .wr_ready (rd_tready),
        .rd_clk   (ft_clk),
        .rd_rst   (rst_ft),
        .rd_data  (cdc_rd_data),
        .rd_valid (cdc_rd_valid),
        .rd_ready (pp_wr_ready)
    );

    la_pingpong_bram #(
        .WORDS (BURST)
    ) u_pp (
        .clk             (ft_clk),
        .rst             (rst_ft),
        .wr_data         (cdc_rd_data),
        .wr_valid        (cdc_rd_valid),
        .wr_ready        (pp_wr_ready),
        .tx_data         (pp_data),
        .tx_valid        (pp_valid),
        .tx_last         (),
        .tx_ready        (pp_ready),
        .overflow_sticky (pp_ovf),
        .dump_active     (dump_active),
        .banks_full      ()
    );

    ft601_sync_fifo #(
        .ALWAYS_DRIVE   (1),
        .TX_BURST_WORDS (BURST)
    ) u_phy (
        .ft_clk   (ft_clk),
        .rst      (rst_ft),
        .ft_data  (ft_data),
        .ft_be    (ft_be),
        .ft_rxf   (ft_rxf),
        .ft_txe   (ft_txe),
        .ft_oe    (ft_oe),
        .ft_rd    (ft_rd),
        .ft_wr    (ft_wr),
        .rx_data  (rx_data),
        .rx_be    (rx_be),
        .rx_valid (rx_valid),
        .rx_ready (1'b0),
        .tx_data  (pp_data),
        .tx_be    (4'hF),
        .tx_valid (pp_valid),
        .tx_ready (pp_ready)
    );

    (* keep = "true" *) wire [31:0] rx_data_keep  = rx_data;
    (* keep = "true" *) wire [3:0]  rx_be_keep    = rx_be;
    (* keep = "true" *) wire        rx_valid_keep = rx_valid;

endmodule
