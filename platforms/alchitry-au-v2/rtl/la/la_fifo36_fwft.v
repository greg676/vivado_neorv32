// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// 1024 x 32 FWFT using FIFO36E1. EN_SYN=FALSE with both clocks tied
// (7-series does not allow FWFT + EN_SYN=TRUE). RDEN is empty-guarded.
module la_fifo36_fwft (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] din,
    input  wire        wr_en,
    output wire        full,
    output wire [31:0] dout,
    input  wire        rd_en,
    output wire        empty
);

    wire [63:0] do64;
    wire        empty_i;
    wire        full_i;

    assign dout  = do64[31:0];
    assign empty = empty_i;
    assign full  = full_i;

    FIFO36E1 #(
        .ALMOST_EMPTY_OFFSET      (13'h0080),
        .ALMOST_FULL_OFFSET       (13'h0080),
        .DATA_WIDTH               (36),
        .DO_REG                   (1),
        .EN_ECC_READ              ("FALSE"),
        .EN_ECC_WRITE             ("FALSE"),
        .EN_SYN                   ("FALSE"),
        .FIFO_MODE                ("FIFO36"),
        .FIRST_WORD_FALL_THROUGH  ("TRUE"),
        .INIT                     (72'h0),
        .SIM_DEVICE               ("7SERIES"),
        .SRVAL                    (72'h0)
    ) u_fifo (
        .DO             (do64),
        .DOP            (),
        .EMPTY          (empty_i),
        .FULL           (full_i),
        .ALMOSTEMPTY    (),
        .ALMOSTFULL     (),
        .RDCOUNT        (),
        .WRCOUNT        (),
        .WRERR          (),
        .RDERR          (),
        .DBITERR        (),
        .SBITERR        (),
        .ECCPARITY      (),
        .DI             ({32'd0, din}),
        .DIP            (4'd0),
        .RDCLK          (clk),
        .WRCLK          (clk),
        .RDEN           (rd_en && !empty_i),
        .WREN           (wr_en && !full_i),
        .RST            (rst),
        .RSTREG         (1'b0),
        .REGCE          (1'b1),
        .INJECTDBITERR  (1'b0),
        .INJECTSBITERR  (1'b0)
    );

endmodule
