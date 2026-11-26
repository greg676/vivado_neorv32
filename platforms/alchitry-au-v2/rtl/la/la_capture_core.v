`timescale 1ns / 1ps
// Stream packed 8-bit LA samples through the PR #18 FT601 PHY.
// NEVER RD: host IN only. ALWAYS_DRIVE so the 4 KiB write bursts stay
// on the proven TX_ONLY pad path (OBUF, Lucid DATA-before-WR).
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
    wire [31:0] tx_data;
    wire        tx_ready;
    wire [31:0] rx_data;
    wire [3:0]  rx_be;
    wire        rx_valid;

    assign source_sel      = SOURCE;
    assign overflow_sticky = 1'b0;
    assign fifo_empty      = 1'b1;
    assign tx_active       = tx_ready;
    assign tx_data         = {s3, s2, s1, s0};

    la_pattern #(
        .SOURCE (SOURCE)
    ) u_pat (
        .clk    (ft_clk),
        .rst    (rst),
        .enable (tx_ready),
        .s0     (s0),
        .s1     (s1),
        .s2     (s2),
        .s3     (s3)
    );

    ft601_sync_fifo #(
        .ALWAYS_DRIVE (1)
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
        .tx_valid (1'b1),
        .tx_ready (tx_ready)
    );

    (* keep = "true" *) wire [31:0] rx_data_keep  = rx_data;
    (* keep = "true" *) wire [3:0]  rx_be_keep    = rx_be;
    (* keep = "true" *) wire        rx_valid_keep = rx_valid;

endmodule
