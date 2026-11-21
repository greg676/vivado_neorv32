`timescale 1ns / 1ps
// Logic-analyzer capture datapath in the ft_clk domain.
// Live pins and on-FPGA patterns are muxed, packed 8→32, then streamed
// with the existing FT601 245 master. Host RX is drained so a leftover
// write cannot stall the PHY. DDR3 is a parallel tap only.
module la_capture_core #(
    parameter integer SAMPLE_MHZ    = 100,
    parameter [1:0]   DEFAULT_SOURCE = 2'd0
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
    output wire [31:0] ddr3_word_count
);

    localparam [1:0] SRC_LIVE = 2'd2;

    wire [31:0] rx_data;
    wire        rx_valid;
    wire        rx_ready = 1'b1;

    wire [31:0] tx_data;
    wire [3:0]  tx_be;
    wire        tx_valid;
    wire        tx_ready;

    reg [1:0] source_r;
    always @(posedge ft_clk) begin
        if (rst)
            source_r <= DEFAULT_SOURCE;
        else if (rx_valid)
            source_r <= rx_data[1:0];
    end
    assign source_sel = source_r;

    wire        use_live = (source_r == SRC_LIVE) || (source_r == 2'd3);
    wire [7:0]  live_s0, live_s1;
    wire [7:0]  pat_s0, pat_s1;
    wire [7:0]  mux_s0 = use_live ? live_s0 : pat_s0;
    wire [7:0]  mux_s1 = use_live ? live_s1 : pat_s1;

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
        .clk    (ft_clk),
        .rst    (rst),
        .source (source_r),
        .s0     (pat_s0),
        .s1     (pat_s1)
    );

    wire [31:0] pack_data;
    wire        pack_valid;

    la_packer #(
        .SAMPLE_MHZ(SAMPLE_MHZ)
    ) u_packer (
        .clk       (ft_clk),
        .rst       (rst),
        .enable    (1'b1),
        .s0        (mux_s0),
        .s1        (mux_s1),
        .out_data  (pack_data),
        .out_valid (pack_valid)
    );

    // Parallel tap — must not backpressure the packer / FT601 path.
    la_ddr3_stub u_ddr3 (
        .clk          (ft_clk),
        .rst          (rst),
        .sample_word  (pack_data),
        .sample_valid (pack_valid),
        .word_count   (ddr3_word_count)
    );

    wire        fifo_full_w;
    wire        fifo_empty_w;
    wire [31:0] fifo_rdata;

    assign fifo_empty = fifo_empty_w;
    assign fifo_full  = fifo_full_w;

    wire wr_en = pack_valid && !fifo_full_w;

    ft601_fwft_fifo #(
        .WIDTH (32),
        .DEPTH (2048),
        .ADDR_W(11)
    ) u_fifo (
        .clk         (ft_clk),
        .rst         (rst),
        .wr_data     (pack_data),
        .wr_en       (wr_en),
        .full        (fifo_full_w),
        .almost_full (),
        .rd_data     (fifo_rdata),
        .rd_en       (tx_ready),
        .empty       (fifo_empty_w),
        .count       ()
    );

    assign tx_data  = fifo_rdata;
    assign tx_be    = 4'hF;
    assign tx_valid = !fifo_empty_w;
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

    reg ovf;
    always @(posedge ft_clk) begin
        if (rst)
            ovf <= 1'b0;
        else if (pack_valid && fifo_full_w)
            ovf <= 1'b1;
    end
    assign overflow_sticky = ovf;

endmodule
