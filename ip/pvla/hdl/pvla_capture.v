`timescale 1ns / 1ps
// PVLA capture datapath: existing LA RTL with the PHY wrapped.
// C_PHY=0 FT601  — ft601_sync_fifo (hidden from BD, pin-file bound)
// C_PHY=1 STREAM — 32-bit AXI-Stream master for a later SuperSpeed FIFO
//
// Does not touch DDR3. la_ddr3_stub remains a parallel tap only.
module pvla_capture #(
    parameter integer C_PHY            = 0,
    parameter integer C_NUM_CH         = 8,
    parameter integer C_SAMPLE_MHZ     = 200,
    parameter integer C_PRETRIG_SAMPLES = 4096,
    parameter integer C_DEFAULT_POST   = 2048,
    parameter [1:0]   C_DEFAULT_SOURCE = 2'd2,
    parameter [2:0]   C_DEFAULT_CH     = 3'd0,
    parameter [1:0]   C_DEFAULT_EDGE   = 2'd0
) (
    input  wire                  cap_clk,
    input  wire                  cap_rst,

    input  wire [C_NUM_CH-1:0]   probe_i,

    // AXI-lite / STREAM command injection (capture domain)
    input  wire                  cmd_valid,
    input  wire [31:0]           cmd_data,

    // FT601 pads — only driven when C_PHY=0
    inout  wire [31:0]           ft_data,
    inout  wire [3:0]            ft_be,
    input  wire                  ft_rxf,
    input  wire                  ft_txe,
    output wire                  ft_oe,
    output wire                  ft_rd,
    output wire                  ft_wr,

    // STREAM master — only driven when C_PHY=1
    output wire [31:0]           m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    output wire                  overflow_sticky,
    output wire                  fifo_empty,
    output wire                  fifo_full,
    output wire                  tx_active,
    output wire [1:0]            source_sel,
    output wire                  armed,
    output wire                  triggered,
    output wire                  cap_done,
    output wire [31:0]           overflow_cnt,
    output wire [31:0]           drop_cnt
);

    localparam integer ADDR_W   = $clog2(C_PRETRIG_SAMPLES);
    localparam [1:0]   SRC_LIVE = 2'd2;

    wire [7:0] probe_pad;
    generate
        if (C_NUM_CH >= 8)
            assign probe_pad = probe_i[7:0];
        else
            assign probe_pad = {{(8-C_NUM_CH){1'b0}}, probe_i};
    endgenerate

    wire [31:0] phy_rx_data;
    wire        phy_rx_valid;
    wire        phy_rx_ready = 1'b1;

    wire [31:0] rx_data  = cmd_valid ? cmd_data : phy_rx_data;
    wire        rx_valid = cmd_valid | phy_rx_valid;

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
        .SAMPLE_MHZ(C_SAMPLE_MHZ)
    ) u_sampler (
        .clk   (cap_clk),
        .rst   (cap_rst),
        .la_in (probe_pad),
        .s0    (live_s0),
        .s1    (live_s1)
    );

    la_pattern #(
        .SAMPLE_MHZ(C_SAMPLE_MHZ)
    ) u_pattern (
        .clk      (cap_clk),
        .rst      (cap_rst),
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
        .SAMPLE_MHZ(C_SAMPLE_MHZ)
    ) u_packer (
        .clk       (cap_clk),
        .rst       (cap_rst),
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
    wire [11:0] fifo_count;

    la_capture_ctrl #(
        .SAMPLE_MHZ     (C_SAMPLE_MHZ),
        .DEFAULT_SOURCE (C_DEFAULT_SOURCE),
        .BUF_DEPTH      (C_PRETRIG_SAMPLES),
        .ADDR_W         (ADDR_W),
        .DEFAULT_POST   (C_DEFAULT_POST),
        .DEFAULT_CH     (C_DEFAULT_CH),
        .DEFAULT_EDGE   (C_DEFAULT_EDGE)
    ) u_ctrl (
        .clk              (cap_clk),
        .rst              (cap_rst),
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

    la_ddr3_stub u_ddr3 (
        .clk          (cap_clk),
        .rst          (cap_rst),
        .sample_word  (fifo_wdata),
        .sample_valid (fifo_wr),
        .word_count   ()
    );

    assign fifo_empty = fifo_empty_w;
    assign fifo_full  = fifo_full_w;

    wire wr_en = fifo_wr && !fifo_full_w;

    ft601_fwft_fifo #(
        .WIDTH (32),
        .DEPTH (2048),
        .ADDR_W(11)
    ) u_fifo (
        .clk         (cap_clk),
        .rst         (cap_rst),
        .wr_data     (fifo_wdata),
        .wr_en       (wr_en),
        .full        (fifo_full_w),
        .almost_full (fifo_afull),
        .rd_data     (fifo_rdata),
        .rd_en       (tx_ready),
        .empty       (fifo_empty_w),
        .count       (fifo_count)
    );

    assign tx_data  = fifo_rdata;
    assign tx_be    = 4'hF;
    assign tx_valid = !fifo_empty_w;

    generate
        if (C_PHY == 0) begin : g_ft601
            ft601_sync_fifo u_phy (
                .ft_clk   (cap_clk),
                .rst      (cap_rst),
                .ft_data  (ft_data),
                .ft_be    (ft_be),
                .ft_rxf   (ft_rxf),
                .ft_txe   (ft_txe),
                .ft_oe    (ft_oe),
                .ft_rd    (ft_rd),
                .ft_wr    (ft_wr),
                .rx_data  (phy_rx_data),
                .rx_be    (),
                .rx_valid (phy_rx_valid),
                .rx_ready (phy_rx_ready),
                .tx_data  (tx_data),
                .tx_be    (tx_be),
                .tx_valid (tx_valid),
                .tx_ready (tx_ready)
            );

            assign m_axis_tdata  = 32'h0;
            assign m_axis_tvalid = 1'b0;
            assign m_axis_tlast  = 1'b0;
            assign tx_active     = tx_ready;
        end else begin : g_stream
            assign phy_rx_data  = 32'h0;
            assign phy_rx_valid = 1'b0;

            assign ft_oe = 1'b1;
            assign ft_rd = 1'b1;
            assign ft_wr = 1'b1;

            assign tx_ready      = m_axis_tready;
            assign m_axis_tdata  = tx_data;
            assign m_axis_tvalid = tx_valid;
            assign m_axis_tlast  = cap_done && tx_valid && (fifo_count == 12'd1);
            assign tx_active     = tx_valid && tx_ready;
        end
    endgenerate

endmodule
