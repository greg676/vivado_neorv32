// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Dedicated FT601 USB3 loopback top for Alchitry Pt V2 + Ft+.
// Does not instantiate NeoRV32. Load this bitstream instead of the SoC
// bitstream when running the host loopback tool.
//
// MODE: "LOOPBACK" (default) or "TX_COUNTER" (set from TCL).
module ft601_loopback_top #(
    parameter MODE = "LOOPBACK"
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [7:0]  led,

    input  wire        ft_clk,
    inout  wire [31:0] ft_data,
    inout  wire [3:0]  ft_be,
    input  wire        ft_rxf,
    input  wire        ft_txe,
    output wire        ft_oe,
    output wire        ft_rd,
    output wire        ft_wr,
    output wire        ft_reset,
    output wire        ft_wakeup
);

    wire rst_ft;

    ft601_reset #(
        .HOLD_CYCLES(100000)
    ) u_reset (
        .clk_board   (clk),
        .rst_n_async (rst_n),
        .ft_clk      (ft_clk),
        .ft_reset    (ft_reset),
        .rst_ft      (rst_ft)
    );

    // WAKEUP_N idle high (inactive).
    assign ft_wakeup = 1'b1;

    wire overflow_sticky;
    wire fifo_empty;
    wire fifo_full;
    wire rx_active;
    wire tx_active;

    ft601_loopback_core #(
        .MODE(MODE)
    ) u_core (
        .ft_clk          (ft_clk),
        .rst             (rst_ft),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf          (ft_rxf),
        .ft_txe          (ft_txe),
        .ft_oe           (ft_oe),
        .ft_rd           (ft_rd),
        .ft_wr           (ft_wr),
        .overflow_sticky (overflow_sticky),
        .fifo_empty      (fifo_empty),
        .fifo_full       (fifo_full),
        .rx_active       (rx_active),
        .tx_active       (tx_active)
    );

    // Heartbeats: board clock and FT601 clock, so a missing ft_clk is obvious.
    reg [24:0] blink_board;
    reg [24:0] blink_ft;
    always @(posedge clk)
        blink_board <= blink_board + 1'b1;
    always @(posedge ft_clk)
        blink_ft <= blink_ft + 1'b1;

    assign led[0] = blink_board[24];
    assign led[1] = blink_ft[24];
    assign led[2] = ~rst_ft;
    assign led[3] = ~fifo_empty;
    assign led[4] = fifo_full;
    assign led[5] = rx_active;
    assign led[6] = tx_active;
    assign led[7] = overflow_sticky;

endmodule
