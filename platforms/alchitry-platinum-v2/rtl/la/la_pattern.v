`timescale 1ns / 1ps
// On-FPGA test patterns, same packing as live samples.
// source 0 : wrapping 8-bit counter
// source 1 : walking-one (0x01, 0x02, ..., 0x80)
// Two samples per clock when SAMPLE_MHZ = 200.
// Outputs are combinational from count so the packer sees sample 0
// on the first enabled cycle (count increments after that edge).
module la_pattern #(
    parameter integer SAMPLE_MHZ = 100
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [1:0] source,
    output wire [7:0] s0,
    output wire [7:0] s1
);

    localparam integer STEP = (SAMPLE_MHZ == 200) ? 2 : 1;

    reg [7:0] count;

    wire [7:0] ctr0  = count;
    wire [7:0] ctr1  = count + 8'd1;
    wire [7:0] walk0 = 8'd1 << count[2:0];
    wire [7:0] walk1 = 8'd1 << (count[2:0] + 3'd1);

    assign s0 = (source == 2'd1) ? walk0 : ctr0;
    assign s1 = (source == 2'd1) ? walk1 : ctr1;

    always @(posedge clk) begin
        if (rst)
            count <= 8'd0;
        else
            count <= count + STEP[7:0];
    end

endmodule
