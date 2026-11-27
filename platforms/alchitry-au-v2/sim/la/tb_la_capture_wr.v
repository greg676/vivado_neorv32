// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Capture core + PR #18 PHY: TXE held low must produce WR pulses.
module tb_la_capture_wr;
    reg         ft_clk = 1'b0;
    reg         rst = 1'b1;
    wire [31:0] ft_data;
    wire [3:0]  ft_be;
    wire        ft_oe, ft_rd, ft_wr;
    wire        overflow_sticky, fifo_empty, tx_active;
    integer     wr_count = 0;
    integer     i;

    assign ft_data = 32'bz;
    assign ft_be   = 4'bz;

    la_capture_core u_core (
        .ft_clk          (ft_clk),
        .rst             (rst),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf          (1'b1),
        .ft_txe          (1'b0),
        .ft_oe           (ft_oe),
        .ft_rd           (ft_rd),
        .ft_wr           (ft_wr),
        .overflow_sticky (overflow_sticky),
        .fifo_empty      (fifo_empty),
        .tx_active       (tx_active),
        .source_sel      ()
    );

    always #5 ft_clk = ~ft_clk;

    always @(posedge ft_clk)
        if (!rst && ft_wr === 1'b0)
            wr_count = wr_count + 1;

    initial begin
        repeat (8) @(posedge ft_clk);
        rst <= 1'b0;
        for (i = 0; i < 3000; i = i + 1)
            @(posedge ft_clk);
        $display("tb_la_capture_wr wr_count=%0d tx_active=%0d ovf=%0d",
                 wr_count, tx_active, overflow_sticky);
        if (wr_count < 1024)
            $display("FAIL tb_la_capture_wr expected a 4 KiB WR burst");
        else
            $display("PASS tb_la_capture_wr");
        $finish;
    end
endmodule
