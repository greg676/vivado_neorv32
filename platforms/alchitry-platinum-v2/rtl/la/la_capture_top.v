// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Dedicated 8-channel logic-analyzer capture top for Alchitry Pt V2 + Ft+ + Br.
// Does not instantiate NeoRV32. Load this bitstream instead of the SoC
// (or the FT601 loopback) when running the host capture dump.
//
// SAMPLE_MHZ     : 100 (SDR) or 200 (DDR @ ft_clk)
// DEFAULT_SOURCE : 0 = counter, 1 = walking-one, 2 = live Br pins
//                  Host may overwrite the low two bits of any TX word.
module la_capture_top #(
    parameter integer SAMPLE_MHZ     = 100,
    parameter [1:0]   DEFAULT_SOURCE = 2'd0
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [7:0]  led,
    input  wire [7:0]  la_in,

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

    assign ft_wakeup = 1'b1;

    wire        overflow_sticky;
    wire        fifo_empty;
    wire        fifo_full;
    wire        tx_active;
    wire [1:0]  source_sel;
    wire [31:0] ddr3_word_count;

    la_capture_core #(
        .SAMPLE_MHZ     (SAMPLE_MHZ),
        .DEFAULT_SOURCE (DEFAULT_SOURCE)
    ) u_core (
        .ft_clk          (ft_clk),
        .rst             (rst_ft),
        .la_in           (la_in),
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
        .tx_active       (tx_active),
        .source_sel      (source_sel),
        .ddr3_word_count (ddr3_word_count)
    );

    reg [24:0] blink_board;
    reg [24:0] blink_ft;
    always @(posedge clk)
        blink_board <= blink_board + 1'b1;
    always @(posedge ft_clk)
        blink_ft <= blink_ft + 1'b1;

    // ddr3_word_count is a Phase-3 hook; do not steer USB with it.
    wire ddr3_hold = ddr3_word_count[0] & 1'b0;

    assign led[0] = blink_board[24];
    assign led[1] = blink_ft[24];
    assign led[2] = ~rst_ft;
    assign led[3] = ~fifo_empty;
    assign led[4] = fifo_full | ddr3_hold;
    assign led[5] = overflow_sticky;
    assign led[6] = (source_sel == 2'd2) || (source_sel == 2'd3);
    assign led[7] = tx_active;

endmodule
