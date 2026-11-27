// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// 8-channel LVCMOS33 sampler in the ft_clk domain (100 MHz).
// SAMPLE_MHZ = 100 : SDR, one sample per rising edge (IOB FF).
// SAMPLE_MHZ = 200 : DDR, two samples per period (IDDR).
module la_sampler #(
    parameter integer SAMPLE_MHZ = 100
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] la_in,
    output wire [7:0] s0,
    output wire [7:0] s1
);

    generate
        if (SAMPLE_MHZ == 200) begin : g_ddr
            genvar i;
            for (i = 0; i < 8; i = i + 1) begin : g_ch
                la_iddr1 u_iddr (
                    .clk    (clk),
                    .rst    (rst),
                    .d      (la_in[i]),
                    .q_rise (s0[i]),
                    .q_fall (s1[i])
                );
            end
        end else begin : g_sdr
            (* IOB = "TRUE" *) reg [7:0] la_q;
            always @(posedge clk) begin
                if (rst)
                    la_q <= 8'd0;
                else
                    la_q <= la_in;
            end
            assign s0 = la_q;
            assign s1 = 8'd0;
        end
    endgenerate

endmodule
