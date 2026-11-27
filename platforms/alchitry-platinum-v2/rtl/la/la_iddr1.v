// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Single-bit 7-series IDDR wrapper.
// SAME_EDGE_PIPELINED: Q_RISE then Q_FALL are the two samples from the
// previous ft_clk period, both presented on the rising edge.
//
// Icarus has no IDDR primitive; SIMULATION selects a behavioural model
// with the same sample order.
module la_iddr1 (
    input  wire clk,
    input  wire rst,
    input  wire d,
    output wire q_rise,
    output wire q_fall
);

`ifdef SIMULATION
    reg d_rise;
    reg d_fall;
    reg q_rise_r;
    reg q_fall_r;

    always @(posedge clk) begin
        if (rst)
            d_rise <= 1'b0;
        else
            d_rise <= d;
    end

    always @(negedge clk) begin
        if (rst)
            d_fall <= 1'b0;
        else
            d_fall <= d;
    end

    always @(posedge clk) begin
        if (rst) begin
            q_rise_r <= 1'b0;
            q_fall_r <= 1'b0;
        end else begin
            q_rise_r <= d_rise;
            q_fall_r <= d_fall;
        end
    end

    assign q_rise = q_rise_r;
    assign q_fall = q_fall_r;
`else
    IDDR #(
        .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
        .INIT_Q1     (1'b0),
        .INIT_Q2     (1'b0),
        .SRTYPE      ("SYNC")
    ) u_iddr (
        .Q1 (q_rise),
        .Q2 (q_fall),
        .C  (clk),
        .CE (1'b1),
        .D  (d),
        .R  (rst),
        .S  (1'b0)
    );
`endif

endmodule
