`timescale 1ns / 1ps
// Simple dual-port circular sample BRAM (inferred block RAM).
// Write port during ARM/POST, read port during dump. Not DDR3 / MIG.
//
// 16-bit entries, one write per ft_clk:
//   100 MS/s : {8'h00, s0}
//   200 MS/s : {s1, s0}   (s0 older)
module la_circ_bram #(
    parameter integer DEPTH  = 4096,
    parameter integer ADDR_W = 12
) (
    input  wire              clk,
    input  wire              wr_en,
    input  wire [ADDR_W-1:0] wr_addr,
    input  wire [15:0]       wr_data,
    input  wire              rd_en,
    input  wire [ADDR_W-1:0] rd_addr,
    output reg  [15:0]       rd_data
);

    (* ram_style = "block" *) reg [15:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    always @(posedge clk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

endmodule
