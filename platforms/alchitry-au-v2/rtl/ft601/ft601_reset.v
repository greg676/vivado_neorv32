// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Lucid Ft Plus demo policy: ft_reset = !button, never a post-DONE pulse.
//
// Alchitry Labs `ft_reset = !rst` with rst only the Pt button (conditioned on
// the board 100 MHz clk). Holding RESET_N after config kills FT601 CLK; this
// module used to do that for ~1 ms, then wait for ft_clk — which never came
// back — so OE/RD stayed idle and host bulk OUT timed out at 0 bytes.
//
// HOLD_CYCLES is accepted so existing instantiations compile; it is unused.
module ft601_reset #(
    parameter integer HOLD_CYCLES = 100000
) (
    input  wire clk_board,
    input  wire rst_n_async,
    input  wire ft_clk,
    output wire ft_reset,
    output wire rst_ft
);

    // Power-up / after DONE: RESET_N already high. Do not start at 0.
    (* ASYNC_REG = "TRUE" *) reg [1:0] btn_n_sync = 2'b11;
    always @(posedge clk_board)
        btn_n_sync <= {btn_n_sync[0], rst_n_async};

    assign ft_reset = btn_n_sync[1];

    wire rst_hold = ~ft_reset;

    // Fabric 245 FSM still needs a defined reset. Init asserted; release on
    // ft_clk. Chip RESET_N is not used as that clock gate.
    (* ASYNC_REG = "TRUE" *) reg [2:0] rst_ft_sync = 3'b111;
    always @(posedge ft_clk or posedge rst_hold) begin
        if (rst_hold)
            rst_ft_sync <= 3'b111;
        else
            rst_ft_sync <= {rst_ft_sync[1:0], 1'b0};
    end

    assign rst_ft = rst_ft_sync[2];

    (* keep = "true" *) wire unused_hold = (HOLD_CYCLES != 0);

endmodule
