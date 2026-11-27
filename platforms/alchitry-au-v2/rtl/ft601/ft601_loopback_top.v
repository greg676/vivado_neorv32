// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Dedicated FT601 USB3 32-bit 245 echo top for Alchitry Au V2 + Ft+.
// Same RTL as the Pt 245 loopback; Au package pins live in XDC.
// Not a multi-channel LA. Does not instantiate NeoRV32.
//
// MODE: "LOOPBACK" (default), "TX_ONLY", or "RX_ONLY" (set from TCL).
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
    wire [31:0] first_rx_word;
    wire        first_rx_valid;

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
        .tx_active       (tx_active),
        .first_rx_word   (first_rx_word),
        .first_rx_valid  (first_rx_valid)
    );

    // Heartbeats: board clock and FT601 clock, so a missing ft_clk is obvious.
    // LED[2] is ~RXF (data available): clock blinks do not change on bulk OUT.
    reg [24:0] blink_board;
    reg [24:0] blink_ft;
    always @(posedge clk)
        blink_board <= blink_board + 1'b1;
    always @(posedge ft_clk)
        blink_ft <= blink_ft + 1'b1;

    generate
        if (MODE == "RX_ONLY") begin : g_rx_led
            // Lower 8 bits of the latched first RX word (USB status via LEDs).
            assign led = first_rx_valid ? first_rx_word[7:0]
                                        : {6'b0, blink_ft[24], blink_board[24]};
        end else begin : g_dbg_led
            assign led[0] = blink_board[24];
            assign led[1] = blink_ft[24];
            assign led[2] = ~ft_rxf;
            assign led[3] = ~fifo_empty;
            assign led[4] = fifo_full;
            assign led[5] = rx_active;
            assign led[6] = tx_active;
            assign led[7] = overflow_sticky;
        end
    endgenerate

endmodule
