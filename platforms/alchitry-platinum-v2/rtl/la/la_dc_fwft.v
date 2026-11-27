// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Dual-clock first-word fall-through FIFO. Same-clock is legal (sim).
// Used to CDC packed LA words between ft_clk and MIG ui_clk.
module la_dc_fwft #(
    parameter integer W     = 32,
    parameter integer DEPTH = 128
) (
    input  wire             wr_clk,
    input  wire             wr_rst,
    input  wire [W-1:0]     wr_data,
    input  wire             wr_valid,
    output wire             wr_ready,

    input  wire             rd_clk,
    input  wire             rd_rst,
    output wire [W-1:0]     rd_data,
    output wire             rd_valid,
    input  wire             rd_ready
);

    localparam integer AW = $clog2(DEPTH);

    (* ram_style = "distributed" *)
    reg [W-1:0] mem [0:DEPTH-1];

    reg  [AW:0] wr_bin, rd_bin;
    reg  [AW:0] wr_gray, rd_gray;
    reg  [AW:0] wr_gray_s1, wr_gray_s2;
    reg  [AW:0] rd_gray_s1, rd_gray_s2;

    function automatic [AW:0] bin2gray;
        input [AW:0] b;
        begin
            bin2gray = b ^ (b >> 1);
        end
    endfunction

    wire [AW:0] wr_bin_n = wr_bin + {{AW{1'b0}}, 1'b1};
    wire [AW:0] rd_bin_n = rd_bin + {{AW{1'b0}}, 1'b1};
    wire [AW:0] wr_gray_n = bin2gray(wr_bin_n);

    // Full when next wr gray equals rd gray with MSBs inverted.
    wire full = (wr_gray_n == {~rd_gray_s2[AW:AW-1], rd_gray_s2[AW-2:0]});
    wire empty = (rd_gray == wr_gray_s2);

    assign wr_ready = ~full;
    assign rd_valid = ~empty;
    assign rd_data  = mem[rd_bin[AW-1:0]];

    always @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_bin  <= { (AW+1){1'b0} };
            wr_gray <= { (AW+1){1'b0} };
        end else if (wr_valid && wr_ready) begin
            mem[wr_bin[AW-1:0]] <= wr_data;
            wr_bin  <= wr_bin_n;
            wr_gray <= wr_gray_n;
        end
    end

    always @(posedge wr_clk) begin
        if (wr_rst) begin
            rd_gray_s1 <= { (AW+1){1'b0} };
            rd_gray_s2 <= { (AW+1){1'b0} };
        end else begin
            rd_gray_s1 <= rd_gray;
            rd_gray_s2 <= rd_gray_s1;
        end
    end

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_bin  <= { (AW+1){1'b0} };
            rd_gray <= { (AW+1){1'b0} };
        end else if (rd_valid && rd_ready) begin
            rd_bin  <= rd_bin_n;
            rd_gray <= bin2gray(rd_bin_n);
        end
    end

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            wr_gray_s1 <= { (AW+1){1'b0} };
            wr_gray_s2 <= { (AW+1){1'b0} };
        end else begin
            wr_gray_s1 <= wr_gray;
            wr_gray_s2 <= wr_gray_s1;
        end
    end

endmodule
