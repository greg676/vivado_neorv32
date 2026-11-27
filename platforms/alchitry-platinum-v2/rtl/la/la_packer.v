// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Pack four 8-bit samples into one little-endian 32-bit FT601 word:
//   [7:0]   = sample t+0  (oldest)
//   [15:8]  = sample t+1
//   [23:16] = sample t+2
//   [31:24] = sample t+3  (newest)
//
// SAMPLE_MHZ = 100 : one sample (s0) per clock, a word every 4 clocks.
// SAMPLE_MHZ = 200 : s0 then s1 each clock, a word every 2 clocks.
module la_packer #(
    parameter integer SAMPLE_MHZ = 100
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [7:0]  s0,
    input  wire [7:0]  s1,
    output reg  [31:0] out_data,
    output reg         out_valid
);

    generate
        if (SAMPLE_MHZ == 200) begin : g_ddr
            reg        phase;
            reg [15:0] acc;

            always @(posedge clk) begin
                if (rst) begin
                    phase     <= 1'b0;
                    acc       <= 16'd0;
                    out_data  <= 32'd0;
                    out_valid <= 1'b0;
                end else begin
                    out_valid <= 1'b0;
                    if (enable) begin
                        if (phase == 1'b0) begin
                            acc   <= {s1, s0};
                            phase <= 1'b1;
                        end else begin
                            out_data  <= {s1, s0, acc};
                            out_valid <= 1'b1;
                            phase     <= 1'b0;
                        end
                    end
                end
            end
        end else begin : g_sdr
            reg [1:0]  idx;
            reg [23:0] acc;

            always @(posedge clk) begin
                if (rst) begin
                    idx       <= 2'd0;
                    acc       <= 24'd0;
                    out_data  <= 32'd0;
                    out_valid <= 1'b0;
                end else begin
                    out_valid <= 1'b0;
                    if (enable) begin
                        case (idx)
                            2'd0: begin
                                acc[7:0] <= s0;
                                idx      <= 2'd1;
                            end
                            2'd1: begin
                                acc[15:8] <= s0;
                                idx       <= 2'd2;
                            end
                            2'd2: begin
                                acc[23:16] <= s0;
                                idx        <= 2'd3;
                            end
                            default: begin
                                out_data  <= {s0, acc};
                                out_valid <= 1'b1;
                                idx       <= 2'd0;
                            end
                        endcase
                    end
                end
            end
        end
    endgenerate

endmodule
