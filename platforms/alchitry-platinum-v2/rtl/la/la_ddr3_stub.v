// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Parallel DDR3 writer stub. NOT in the USB streaming path.
// Counts packed words so the insertion point exists; Phase 3 replaces
// this with MIG pre-trigger DMA. Do not add ready/backpressure here.
module la_ddr3_stub (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] sample_word,
    input  wire        sample_valid,
    output wire [31:0] word_count
);

    reg [31:0] count_r;

    always @(posedge clk) begin
        if (rst)
            count_r <= 32'd0;
        else if (sample_valid)
            count_r <= count_r + 1'b1;
    end

    assign word_count = count_r;

    // sample_word is a Phase-3 hook (payload for MIG). It is not forwarded
    // to FT601 TX; the keep net only exists so the port is not stripped.
    (* keep = "true" *) wire [31:0] keep_word;
    assign keep_word = sample_word;

endmodule
