// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Four consecutive 8-bit samples per clock, advanced only when enable.
// Enable is ping-pong wr_ready (FIFO has room), not PHY tx_ready / TXE.
// Dual 4 KiB FWFT BRAMs keep every FT601 write a full 4 KiB burst.
//
// SOURCE 0 : wrapping 8-bit counter
// SOURCE 1 : walking-one (0x01, 0x02, ..., 0x80)
module la_pattern #(
    parameter [1:0] SOURCE = 2'd0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    output wire [7:0]  s0,
    output wire [7:0]  s1,
    output wire [7:0]  s2,
    output wire [7:0]  s3
);

    reg [31:0] n;

    function automatic [7:0] samp;
        input [31:0] idx;
        begin
            if (SOURCE == 2'd1)
                samp = 8'd1 << idx[2:0];
            else
                samp = idx[7:0];
        end
    endfunction

    assign s0 = samp(n);
    assign s1 = samp(n + 32'd1);
    assign s2 = samp(n + 32'd2);
    assign s3 = samp(n + 32'd3);

    always @(posedge clk) begin
        if (rst)
            n <= 32'd0;
        else if (enable)
            n <= n + 32'd4;
    end

endmodule
