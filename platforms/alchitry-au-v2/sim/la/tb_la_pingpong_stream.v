`timescale 1ns / 1ps
// Concurrent fill+dump from reset — the silicon IN path.
module tb_la_pingpong_stream;
    localparam integer N = 64;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    wire [31:0] wr_data;
    wire        wr_ready;
    wire [31:0] tx_data;
    wire        tx_valid;
    reg         tx_ready = 1'b0;
    wire        overflow_sticky;
    integer     errors = 0;
    integer     got_n = 0;
    integer     i;
    reg  [31:0] exp;

    wire [7:0] s0, s1, s2, s3;
    assign wr_data = {s3, s2, s1, s0};

    la_pattern u_pat (
        .clk    (clk),
        .rst    (rst),
        .enable (wr_ready),
        .s0     (s0),
        .s1     (s1),
        .s2     (s2),
        .s3     (s3)
    );

    la_pingpong_bram #(.WORDS(1024)) u_pp (
        .clk             (clk),
        .rst             (rst),
        .wr_data         (wr_data),
        .wr_valid        (1'b1),
        .wr_ready        (wr_ready),
        .tx_data         (tx_data),
        .tx_valid        (tx_valid),
        .tx_last         (),
        .tx_ready        (tx_ready),
        .overflow_sticky (overflow_sticky),
        .dump_active     (),
        .banks_full      ()
    );

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        tx_ready <= 1'b1;
        exp = {8'd3, 8'd2, 8'd1, 8'd0};
        while (got_n < N) begin
            @(posedge clk);
            if (tx_valid && tx_ready) begin
                if (tx_data !== exp) begin
                    if (errors < 16)
                        $display("FAIL n=%0d got=0x%08x exp=0x%08x",
                                 got_n, tx_data, exp);
                    errors = errors + 1;
                end
                exp   = exp + 32'h04040404;
                got_n = got_n + 1;
            end
        end
        if (errors == 0)
            $display("PASS tb_la_pingpong_stream got=%0d", got_n);
        else
            $display("FAIL tb_la_pingpong_stream errors=%0d", errors);
        $finish;
    end
endmodule
