`timescale 1ns / 1ps
// Logic-analyzer capture datapath in the ft_clk domain.
// Live pins and on-FPGA patterns are muxed, edge-triggered into a BRAM
// circular pre-trigger, then dumped over the existing FT601 245 master.
// Host RX carries start/stop/cfg; leftover writes cannot stall the PHY
// because RX is always accepted. DDR3 is still a parallel tap only.
module la_capture_core #(
    parameter integer SAMPLE_MHZ     = 100,
    parameter [1:0]   DEFAULT_SOURCE = 2'd0,
    parameter integer BUF_DEPTH      = 4096,
    parameter integer DEFAULT_POST   = 2048,
    parameter [2:0]   DEFAULT_CH     = 3'd0,
    parameter [1:0]   DEFAULT_EDGE   = 2'd0
) (
    input  wire        ft_clk,
    input  wire        rst,
    input  wire [7:0]  la_in,

    inout  wire [31:0] ft_data,
    inout  wire [3:0]  ft_be,
    input  wire        ft_rxf,
    input  wire        ft_txe,
    output wire        ft_oe,
    output wire        ft_rd,
    output wire        ft_wr,

    output wire        overflow_sticky,
    output wire        fifo_empty,
    output wire        fifo_full,
    output wire        tx_active,
    output wire [1:0]  source_sel,
    output wire        armed,
    output wire        triggered,
    output wire        cap_done,
    output wire [31:0] overflow_cnt,
    output wire [31:0] drop_cnt,
    output wire [31:0] ddr3_word_count
);

    localparam integer ADDR_W   = $clog2(BUF_DEPTH);
    localparam [1:0]   SRC_LIVE = 2'd2;

    wire [31:0] rx_data;
    wire        rx_valid;
    wire        rx_ready = 1'b1;

    wire [31:0] tx_data;
    wire [3:0]  tx_be;
    wire        tx_valid;
    wire        tx_ready;

    wire [1:0]  source_r;
    wire        pattern_en;
    wire        pattern_rst;

    wire [7:0]  live_s0, live_s1;
    wire [7:0]  pat_s0, pat_s1;
    wire        use_live = (source_r == SRC_LIVE) || (source_r == 2'd3);
    wire [7:0]  mux_s0 = use_live ? live_s0 : pat_s0;
    wire [7:0]  mux_s1 = use_live ? live_s1 : pat_s1;

    assign source_sel = source_r;

    la_sampler #(
        .SAMPLE_MHZ(SAMPLE_MHZ)
    ) u_sampler (
        .clk   (ft_clk),
        .rst   (rst),
        .la_in (la_in),
        .s0    (live_s0),
        .s1    (live_s1)
    );

    la_pattern #(
        .SAMPLE_MHZ(SAMPLE_MHZ)
    ) u_pattern (
        .clk      (ft_clk),
        .rst      (rst),
        .enable   (pattern_en),
        .soft_rst (pattern_rst),
        .source   (source_r),
        .s0       (pat_s0),
        .s1       (pat_s1)
    );

    wire [7:0]  pack_s0, pack_s1;
    wire        pack_en;
    wire [31:0] pack_data;
    wire        pack_valid;

    la_packer #(
        .SAMPLE_MHZ(SAMPLE_MHZ)
    ) u_packer (
        .clk       (ft_clk),
        .rst       (rst),
        .enable    (pack_en),
        .s0        (pack_s0),
        .s1        (pack_s1),
        .out_data  (pack_data),
        .out_valid (pack_valid)
    );

    wire [31:0] fifo_wdata;
    wire        fifo_wr;
    wire        fifo_full_w;
    wire        fifo_empty_w;
    wire        fifo_afull;
    wire [31:0] fifo_rdata;

    la_capture_ctrl #(
        .SAMPLE_MHZ     (SAMPLE_MHZ),
        .DEFAULT_SOURCE (DEFAULT_SOURCE),
        .BUF_DEPTH      (BUF_DEPTH),
        .ADDR_W         (ADDR_W),
        .DEFAULT_POST   (DEFAULT_POST),
        .DEFAULT_CH     (DEFAULT_CH),
        .DEFAULT_EDGE   (DEFAULT_EDGE)
    ) u_ctrl (
        .clk              (ft_clk),
        .rst              (rst),
        .s0               (mux_s0),
        .s1               (mux_s1),
        .rx_valid         (rx_valid),
        .rx_data          (rx_data),
        .source_sel       (source_r),
        .pattern_en       (pattern_en),
        .pattern_rst      (pattern_rst),
        .pack_s0          (pack_s0),
        .pack_s1          (pack_s1),
        .pack_en          (pack_en),
        .pack_data        (pack_data),
        .pack_valid       (pack_valid),
        .fifo_wdata       (fifo_wdata),
        .fifo_wr          (fifo_wr),
        .fifo_full        (fifo_full_w),
        .fifo_almost_full (fifo_afull),
        .armed            (armed),
        .triggered_o      (triggered),
        .cap_done         (cap_done),
        .overflow_sticky  (overflow_sticky),
        .overflow_cnt     (overflow_cnt),
        .drop_cnt         (drop_cnt)
    );

    // Parallel tap — must not backpressure the packer / FT601 path.
    la_ddr3_stub u_ddr3 (
        .clk          (ft_clk),
        .rst          (rst),
        .sample_word  (fifo_wdata),
        .sample_valid (fifo_wr),
        .word_count   (ddr3_word_count)
    );

    assign fifo_empty = fifo_empty_w;
    assign fifo_full  = fifo_full_w;

    wire wr_en = fifo_wr && !fifo_full_w;

    ft601_fwft_fifo #(
        .WIDTH (32),
        .DEPTH (2048),
        .ADDR_W(11)
    ) u_fifo (
        .clk         (ft_clk),
        .rst         (rst),
        .wr_data     (fifo_wdata),
        .wr_en       (wr_en),
        .full        (fifo_full_w),
        .almost_full (fifo_afull),
        .rd_data     (fifo_rdata),
        .rd_en       (tx_ready),
        .empty       (fifo_empty_w),
        .count       ()
    );

    assign tx_data   = fifo_rdata;
    assign tx_be     = 4'hF;
    assign tx_valid  = !fifo_empty_w;
    assign tx_active = tx_ready;

    ft601_sync_fifo u_phy (
        .ft_clk   (ft_clk),
        .rst      (rst),
        .ft_data  (ft_data),
        .ft_be    (ft_be),
        .ft_rxf   (ft_rxf),
        .ft_txe   (ft_txe),
        .ft_oe    (ft_oe),
        .ft_rd    (ft_rd),
        .ft_wr    (ft_wr),
        .rx_data  (rx_data),
        .rx_be    (),
        .rx_valid (rx_valid),
        .rx_ready (rx_ready),
        .tx_data  (tx_data),
        .tx_be    (tx_be),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready)
    );

endmodule
