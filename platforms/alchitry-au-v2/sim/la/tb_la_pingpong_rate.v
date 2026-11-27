`timescale 1ns / 1ps
// FWFT dual-BRAM must keep tx_valid solid (PHY drops WRITE on a bubble)
// and dump consecutive packed words through 4 KiB-cadence tx_ready gaps.
module tb_la_pingpong_rate;
    localparam integer WORDS = 1024;
    localparam integer NDUMP = 8192;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    wire [31:0] wr_data;
    wire        wr_ready;
    wire [31:0] tx_data;
    wire        tx_valid;
    reg         tx_ready = 1'b0;
    wire        overflow_sticky;
    wire [7:0]  s0, s1, s2, s3;

    integer     errors = 0;
    integer     got_n = 0;
    integer     bubbles = 0;
    integer     seen_valid = 0;
    integer     i;
    integer     pause;
    integer     got_burst;
    integer     gaps;
    integer     stalled;
    reg [31:0]  exp;
    reg         prev_valid;

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

    la_pingpong_bram #(.WORDS(WORDS)) u_pp (
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
        exp = {8'd3, 8'd2, 8'd1, 8'd0};
        prev_valid = 1'b0;
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        tx_ready <= 1'b1;

        // 1. Continuous ready: consecutive packed words, no tx_valid bubble
        //    after the first valid (warmup is BRAM latency only).
        while (got_n < NDUMP) begin
            @(posedge clk);
            if (tx_valid && tx_ready) begin
                if (tx_data !== exp) begin
                    if (errors < 16)
                        $display("FAIL cont n=%0d got=0x%08x exp=0x%08x",
                                 got_n, tx_data, exp);
                    errors = errors + 1;
                end
                exp        = {exp[7:0]+8'd7, exp[7:0]+8'd6, exp[7:0]+8'd5, exp[7:0]+8'd4};
                got_n      = got_n + 1;
                seen_valid = 1;
            end else if (seen_valid && !tx_valid) begin
                bubbles = bubbles + 1;
                if (bubbles <= 8)
                    $display("FAIL bubble at n=%0d", got_n);
            end
        end
        if (bubbles != 0) begin
            $display("FAIL continuous tx_valid bubbles=%0d (PHY would drop WRITE)",
                     bubbles);
            errors = errors + 1;
        end
        $display("continuous: dumped=%0d bubbles=%0d", got_n, bubbles);

        // 2. PHY 4 KiB burst: 1024 ready, 2 stall (IDLE + TXE sample), x8.
        seen_valid = 0;
        bubbles = 0;
        gaps = 0;
        stalled = 0;
        for (i = 0; i < 8; i = i + 1) begin
            tx_ready <= 1'b1;
            got_burst = 0;
            while (got_burst < WORDS) begin
                @(posedge clk);
                if (tx_valid && tx_ready) begin
                    if (tx_data !== exp) begin
                        if (errors < 16)
                            $display("FAIL burst i=%0d n=%0d got=0x%08x exp=0x%08x",
                                     i, got_n, tx_data, exp);
                        errors = errors + 1;
                    end
                    exp        = {exp[7:0]+8'd7, exp[7:0]+8'd6, exp[7:0]+8'd5, exp[7:0]+8'd4};
                    got_n      = got_n + 1;
                    got_burst  = got_burst + 1;
                    seen_valid = 1;
                end else if (seen_valid && tx_ready && !tx_valid) begin
                    bubbles = bubbles + 1;
                    if (bubbles <= 8)
                        $display("FAIL burst-bubble i=%0d n=%0d", i, got_n);
                end
            end
            tx_ready <= 1'b0;
            seen_valid = 0;
            for (pause = 0; pause < 2; pause = pause + 1) begin
                @(posedge clk);
                if (wr_ready)
                    gaps = gaps + 1;
                else
                    stalled = stalled + 1;
            end
        end
        if (bubbles != 0) begin
            $display("FAIL 4 KiB burst tx_valid bubbles=%0d", bubbles);
            errors = errors + 1;
        end
        if (stalled != 0) begin
            $display("FAIL sampler stalled on 2-cycle burst gap (%0d)", stalled);
            errors = errors + 1;
        end
        $display("4KiB cadence: dumped=%0d burst_bubbles=%0d wr_ready_gap=%0d",
                 got_n, bubbles, gaps);

        if (overflow_sticky) begin
            $display("FAIL overflow_sticky");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS tb_la_pingpong_rate dumped=%0d", got_n);
        else
            $display("FAIL tb_la_pingpong_rate errors=%0d", errors);
        $finish;
    end
endmodule
