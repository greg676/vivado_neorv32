`timescale 1ns / 1ps
// Dual 4 KiB BRAM: sampler must keep filling while TXE / tx_ready is low.
module tb_la_pingpong;
    localparam integer WORDS = 1024;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [31:0] wr_data = 32'd0;
    reg         wr_valid = 1'b0;
    wire        wr_ready;
    wire [31:0] tx_data;
    wire        tx_valid;
    reg         tx_ready = 1'b0;
    wire        overflow_sticky;
    wire        dump_active;
    wire [1:0]  banks_full;

    integer     errors = 0;
    integer     i;
    integer     got_n;
    integer     filled;
    integer     stalled;
    integer     gaps;
    integer     dumped;
    integer     pause;
    reg  [31:0] next_exp;

    la_pingpong_bram #(.WORDS(WORDS)) u_pp (
        .clk             (clk),
        .rst             (rst),
        .wr_data         (wr_data),
        .wr_valid        (wr_valid),
        .wr_ready        (wr_ready),
        .tx_data         (tx_data),
        .tx_valid        (tx_valid),
        .tx_last         (),
        .tx_ready        (tx_ready),
        .overflow_sticky (overflow_sticky),
        .dump_active     (dump_active),
        .banks_full      (banks_full)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst) begin
            wr_data <= 32'd0;
        end else if (wr_valid && wr_ready) begin
            wr_data <= wr_data + 32'd1;
        end
    end

    task automatic drain_n;
        input integer n;
        integer k;
        begin
            k = 0;
            while (k < n) begin
                @(posedge clk);
                if (tx_valid && tx_ready) begin
                    if (tx_data !== next_exp) begin
                        if (errors < 8)
                            $display("FAIL dump k=%0d got=0x%08x exp=0x%08x",
                                     k, tx_data, next_exp);
                        errors = errors + 1;
                    end
                    next_exp = next_exp + 32'd1;
                    k = k + 1;
                end
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);

        // 1. TXE high (tx_ready=0): sampler fills both 4 KiB banks, then
        //    wr_ready drops. Pattern must not be gated on tx_ready.
        wr_valid <= 1'b1;
        tx_ready <= 1'b0;
        filled = 0;
        stalled = 0;
        for (i = 0; i < (2 * WORDS + 64); i = i + 1) begin
            @(posedge clk);
            if (wr_ready)
                filled = filled + 1;
            else
                stalled = stalled + 1;
        end
        if (filled != 2 * WORDS) begin
            $display("FAIL filled %0d words, want %0d (two 4 KiB banks)",
                     filled, 2 * WORDS);
            errors = errors + 1;
        end
        if (stalled == 0) begin
            $display("FAIL wr_ready never dropped after both banks full");
            errors = errors + 1;
        end
        if (banks_full !== 2'b11) begin
            $display("FAIL banks_full=%b after TXE-hold fill", banks_full);
            errors = errors + 1;
        end
        $display("hold-TXE: filled=%0d stalled=%0d banks=%b ovf=%0d",
                 filled, stalled, banks_full, overflow_sticky);

        // 2. Dump both banks. First word must be 0 (no extra/stale word).
        next_exp = 32'd0;
        tx_ready <= 1'b1;
        drain_n(2 * WORDS);
        if (next_exp !== 32'd2048) begin
            $display("FAIL after dual dump next_exp=%0d", next_exp);
            errors = errors + 1;
        end
        $display("dump both banks: words 0..2047 OK");

        // Fill continued during the dump (no drain-to-empty). Pause the
        // writer and empty the FIFO so the TXE-gap stream starts with slack.
        wr_valid <= 1'b0;
        while (tx_valid) begin
            @(posedge clk);
            if (tx_valid && tx_ready) begin
                if (tx_data !== next_exp) begin
                    if (errors < 16)
                        $display("FAIL drain-empty got=0x%08x exp=0x%08x",
                                 tx_data, next_exp);
                    errors = errors + 1;
                end
                next_exp = next_exp + 32'd1;
            end
        end
        wr_valid <= 1'b1;
        @(posedge clk);

        // 3. Streaming with TXE gaps: 1024 ready, 32 stall, repeat.
        //    Start from empty so used stays off the high-water mark.
        //    Sampler must keep filling (wr_ready stays 1) through the
        //    32-cycle TXE-high window.
        dumped = 0;
        gaps = 0;
        stalled = 0;
        for (i = 0; i < 8; i = i + 1) begin
            tx_ready <= 1'b1;
            got_n = 0;
            while (got_n < WORDS) begin
                @(posedge clk);
                if (tx_valid && tx_ready) begin
                    if (tx_data !== next_exp) begin
                        if (errors < 16)
                            $display("FAIL stream i=%0d got=0x%08x exp=0x%08x",
                                     i, tx_data, next_exp);
                        errors = errors + 1;
                    end
                    next_exp = next_exp + 32'd1;
                    got_n = got_n + 1;
                    dumped = dumped + 1;
                end
            end
            tx_ready <= 1'b0;
            for (pause = 0; pause < 32; pause = pause + 1) begin
                @(posedge clk);
                if (wr_ready)
                    gaps = gaps + 1;
                else
                    stalled = stalled + 1;
            end
        end
        if (dumped != 8 * WORDS) begin
            $display("FAIL streamed %0d, want %0d", dumped, 8 * WORDS);
            errors = errors + 1;
        end
        if (gaps != 8 * 32) begin
            $display("FAIL sampler stalled on TXE gap (wr_ready cycles=%0d)",
                     gaps);
            errors = errors + 1;
        end
        if (stalled != 0) begin
            $display("FAIL sampler stalled on TXE (wr_ready=0 for %0d gap cycles)",
                     stalled);
            errors = errors + 1;
        end
        $display("TXE gaps: dumped=%0d sampler_ran_during_gap=%0d stall_on_TXE=%0d",
                 dumped, gaps, stalled);

        if (errors == 0)
            $display("PASS tb_la_pingpong");
        else
            $display("FAIL tb_la_pingpong errors=%0d", errors);
        $finish;
    end
endmodule
