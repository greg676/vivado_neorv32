`timescale 1ns / 1ps
// Edge trigger on one of 8 channels.
// SAMPLE_MHZ = 100 : test s0 against the previous sample.
// SAMPLE_MHZ = 200 : test prev→s0 then s0→s1; the earlier hit wins.
//
// edge_mode: 0 rising, 1 falling, 2 both, 3 immediate (first enabled sample).
// hit is combinational so the triggering sample is written the same cycle.
module la_trig #(
    parameter integer SAMPLE_MHZ = 100
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire [7:0] s0,
    input  wire [7:0] s1,
    input  wire [2:0] channel,
    input  wire [1:0] edge_mode,
    output wire       hit,
    output wire       hit_s1
);

    localparam [1:0] EDGE_RISE = 2'd0;
    localparam [1:0] EDGE_FALL = 2'd1;
    localparam [1:0] EDGE_BOTH = 2'd2;
    localparam [1:0] EDGE_IMM  = 2'd3;

    reg prev;
    reg have_prev;

    wire b0 = s0[channel];
    wire b1 = s1[channel];

    wire rise0 = ~prev &  b0;
    wire fall0 =  prev & ~b0;
    wire rise1 = ~b0  &  b1;
    wire fall1 =  b0  & ~b1;

    wire m0 = (edge_mode == EDGE_RISE) ? rise0 :
              (edge_mode == EDGE_FALL) ? fall0 :
              (edge_mode == EDGE_BOTH) ? (rise0 | fall0) : 1'b0;
    wire m1 = (edge_mode == EDGE_RISE) ? rise1 :
              (edge_mode == EDGE_FALL) ? fall1 :
              (edge_mode == EDGE_BOTH) ? (rise1 | fall1) : 1'b0;

    wire match0 = have_prev & m0;
    wire match1 = have_prev & m1 & (SAMPLE_MHZ == 200);

    assign hit    = enable & ((edge_mode == EDGE_IMM) | match0 | match1);
    assign hit_s1 = enable & (edge_mode != EDGE_IMM) & ~match0 & match1;

    always @(posedge clk) begin
        if (rst || !enable) begin
            prev      <= 1'b0;
            have_prev <= 1'b0;
        end else begin
            have_prev <= 1'b1;
            prev      <= (SAMPLE_MHZ == 200) ? b1 : b0;
        end
    end

endmodule
