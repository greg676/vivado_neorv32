// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// First-word fall-through FIFO (distributed RAM).
// Loopback echo uses WIDTH=32 (DATA only; TX BE is forced 0xF).
module ft601_fwft_fifo #(
    parameter WIDTH  = 36,
    parameter DEPTH  = 512,
    parameter ADDR_W = 9
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] wr_data,
    input  wire             wr_en,
    output wire             full,
    output wire             almost_full,
    output wire [WIDTH-1:0] rd_data,
    input  wire             rd_en,
    output wire             empty,
    output wire [ADDR_W:0]  count
);

    (* ram_style = "distributed" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [ADDR_W:0]   count_r;

    wire wr_fire = wr_en && !full;
    wire rd_fire = rd_en && !empty;

    assign count       = count_r;
    assign empty       = (count_r == { (ADDR_W+1){1'b0} });
    assign full        = (count_r == DEPTH[ADDR_W:0]);
    assign almost_full = (count_r >= (DEPTH[ADDR_W:0] - 16));
    assign rd_data     = mem[rd_ptr];

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr  <= {ADDR_W{1'b0}};
            rd_ptr  <= {ADDR_W{1'b0}};
            count_r <= { (ADDR_W+1){1'b0} };
        end else begin
            if (wr_fire)
                mem[wr_ptr] <= wr_data;

            if (wr_fire)
                wr_ptr <= wr_ptr + 1'b1;
            if (rd_fire)
                rd_ptr <= rd_ptr + 1'b1;

            if (wr_fire && !rd_fire)
                count_r <= count_r + 1'b1;
            else if (!wr_fire && rd_fire)
                count_r <= count_r - 1'b1;
        end
    end

endmodule
