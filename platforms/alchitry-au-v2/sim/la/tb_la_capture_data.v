`timescale 1ns / 1ps
// Capture core + PHY: packed counter on WR across several 4 KiB bursts.
// TX-only keeps WR low for 1024 cycles then 1 IDLE. Dual-BRAM must match
// that cadence (no mid-burst WR bubble) and stay consecutive.
module tb_la_capture_data;
    localparam integer BURSTS = 8;
    localparam integer WANT   = BURSTS * 1024;

    reg         ft_clk = 1'b0;
    reg         rst = 1'b1;
    wire [31:0] ft_data;
    wire [3:0]  ft_be;
    wire        ft_oe, ft_rd, ft_wr;
    integer     errors = 0;
    integer     got_n = 0;
    integer     i;
    integer     b;
    integer     wr_low = 0;
    integer     wr_high = 0;
    integer     mid_bubbles = 0;
    integer     burst_pos = 0;
    integer     seen_wr = 0;
    reg [31:0]  exp;
    reg [31:0]  data_d;
    reg         wr_d;

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
        .overflow_sticky (),
        .fifo_empty      (),
        .tx_active       (),
        .source_sel      ()
    );

    always #5 ft_clk = ~ft_clk;

    always @(posedge ft_clk) begin
        data_d <= ft_data;
        wr_d   <= ft_wr;
    end

    initial begin
        repeat (8) @(posedge ft_clk);
        rst <= 1'b0;
        i = 0;
        while (i < (WANT * 2 + 64) && got_n < WANT) begin
            @(posedge ft_clk);
            i = i + 1;
            if (rst) begin
            end else if (ft_wr === 1'b0) begin
                wr_low = wr_low + 1;
                b = got_n * 4;
                exp = {b[7:0]+8'd3, b[7:0]+8'd2, b[7:0]+8'd1, b[7:0]};
                if (ft_data !== exp && data_d !== exp) begin
                    if (errors < 12)
                        $display("FAIL n=%0d pad=0x%08x dly=0x%08x exp=0x%08x",
                                 got_n, ft_data, data_d, exp);
                    errors = errors + 1;
                end
                got_n = got_n + 1;
                burst_pos = burst_pos + 1;
                if (burst_pos == 1024)
                    burst_pos = 0;
                seen_wr = 1;
            end else begin
                wr_high = wr_high + 1;
                if (seen_wr && burst_pos != 0 && burst_pos != 1024) begin
                    mid_bubbles = mid_bubbles + 1;
                    if (mid_bubbles <= 8)
                        $display("FAIL mid-burst WR bubble at n=%0d pos=%0d",
                                 got_n, burst_pos);
                end
            end
        end
        $display("tb_la_capture_data got=%0d wr_low=%0d wr_high=%0d mid_bubbles=%0d errors=%0d",
                 got_n, wr_low, wr_high, mid_bubbles, errors);
        if (got_n < WANT) begin
            $display("FAIL short dump %0d < %0d", got_n, WANT);
            errors = errors + 1;
        end
        if (mid_bubbles != 0) begin
            $display("FAIL PHY WR bubbles mid 4 KiB burst");
            errors = errors + 1;
        end
        if (got_n >= WANT && errors == 0)
            $display("PASS tb_la_capture_data");
        else
            $display("FAIL tb_la_capture_data");
        $finish;
    end
endmodule
