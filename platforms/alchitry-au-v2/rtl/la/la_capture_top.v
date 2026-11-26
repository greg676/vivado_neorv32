`timescale 1ns / 1ps
// Dedicated 8-channel LA capture top for Alchitry Au V2 + Ft+.
// Same FT601 pads as the 245 loopback. Does not instantiate NeoRV32.
// Dual 4 KiB BRAM ping-pong in front of the PR #18 PHY so the sampler
// never stalls on TXE. Host IN 4 KiB PHY bursts (~400 MB/s @ 32-bit 100 MHz).
//
// SOURCE: 0 = wrapping 8-bit counter, 1 = walking-one.
module la_capture_top #(
    parameter [1:0] SOURCE = 2'd0
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

    assign ft_wakeup = 1'b1;

    wire       overflow_sticky;
    wire       fifo_empty;
    wire       tx_active;
    wire [1:0] source_sel;

    la_capture_core #(
        .SOURCE (SOURCE)
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
        .tx_active       (tx_active),
        .source_sel      (source_sel)
    );

    reg [24:0] blink_board;
    reg [24:0] blink_ft;
    always @(posedge clk)
        blink_board <= blink_board + 1'b1;
    always @(posedge ft_clk)
        blink_ft <= blink_ft + 1'b1;

    assign led[0] = blink_board[24];
    assign led[1] = blink_ft[24];
    assign led[2] = ~rst_ft;
    assign led[3] = tx_active;
    assign led[4] = fifo_empty;
    assign led[5] = overflow_sticky;
    assign led[6] = source_sel[0];
    assign led[7] = source_sel[1];

endmodule
