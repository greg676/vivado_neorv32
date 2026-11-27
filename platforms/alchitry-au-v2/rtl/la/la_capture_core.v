`timescale 1ns / 1ps
// Stream packed 8-bit LA samples through two 4 KiB BRAM banks, then the
// PR #18 FT601 PHY. NEVER RD: host IN only. ALWAYS_DRIVE so the 4 KiB
// write bursts stay on the proven TX_ONLY pad path (OBUF, Lucid
// DATA-before-WR).
//
// Sampler enable is ping-pong wr_ready, not PHY tx_ready / TXE. TXE only
// pauses the dump pop. Cascaded FIFO36 FWFT keeps tx_valid solid so
// ST_WRITE does not drop mid-burst (TX-only cadence). Target: 4 bytes/clock
// @ 100 MHz ≈ 400 MB/s.
module la_capture_core #(
    parameter [1:0] SOURCE = 2'd0
) (
    input  wire        ft_clk,
    input  wire        rst,

    inout  wire [31:0] ft_data,
    inout  wire [3:0]  ft_be,
    input  wire        ft_rxf,
    input  wire        ft_txe,
    output wire        ft_oe,
    output wire        ft_rd,
    output wire        ft_wr,

    output wire        overflow_sticky,
    output wire        fifo_empty,
    output wire        tx_active,
    output wire [1:0]  source_sel
);

    wire [7:0]  s0, s1, s2, s3;
    wire [31:0] samp_word;
    wire        wr_ready;
    wire [31:0] tx_data;
    wire        tx_valid;
    wire        tx_ready;
    wire        dump_active;
    wire [31:0] rx_data;
    wire [3:0]  rx_be;
    wire        rx_valid;

    assign source_sel = SOURCE;
    assign samp_word  = {s3, s2, s1, s0};
    assign fifo_empty = ~tx_valid;
    assign tx_active  = dump_active;

    la_pattern #(
        .SOURCE (SOURCE)
    ) u_pat (
        .clk    (ft_clk),
        .rst    (rst),
        .enable (wr_ready),
        .s0     (s0),
        .s1     (s1),
        .s2     (s2),
        .s3     (s3)
    );

    la_pingpong_bram #(
        .WORDS (1024)
    ) u_pp (
        .clk             (ft_clk),
        .rst             (rst),
        .wr_data         (samp_word),
        .wr_valid        (1'b1),
        .wr_ready        (wr_ready),
        .tx_data         (tx_data),
        .tx_valid        (tx_valid),
        .tx_last         (),
        .tx_ready        (tx_ready),
        .overflow_sticky (overflow_sticky),
        .dump_active     (dump_active),
        .banks_full      ()
    );

    ft601_sync_fifo #(
        .ALWAYS_DRIVE   (1),
        .TX_BURST_WORDS (1024)
    ) u_phy (
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
        .rx_be    (rx_be),
        .rx_valid (rx_valid),
        .rx_ready (1'b0),
        .tx_data  (tx_data),
        .tx_be    (4'hF),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready)
    );

    (* keep = "true" *) wire [31:0] rx_data_keep  = rx_data;
    (* keep = "true" *) wire [3:0]  rx_be_keep    = rx_be;
    (* keep = "true" *) wire        rx_valid_keep = rx_valid;

endmodule
