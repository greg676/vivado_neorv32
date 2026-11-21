`timescale 1ns / 1ps
// Extra trigger-engine cases: fall/both, STOP, FORCE, overflow/drop, channel 3.
module tb_la_trigger;

    localparam integer BUF_DEPTH = 32;
    localparam integer HDR_WORDS = 8;
    localparam [31:0]  MAGIC     = 32'h3354414C;
    localparam [3:0]   CMD_START = 4'd2;
    localparam [3:0]   CMD_STOP  = 4'd3;
    localparam [3:0]   CMD_FORCE = 4'd4;

    reg         clk;
    reg         rst_chip;
    reg         rst_dut;
    wire [31:0] ft_data;
    wire [3:0]  ft_be;
    wire        ft_rxf;
    wire        ft_txe;
    wire        ft_oe;
    wire        ft_rd;
    wire        ft_wr;

    reg         host_push_en;
    reg  [31:0] host_push_data;
    wire        host_push_full;
    reg         host_pop_en;
    wire [31:0] host_pop_data;
    wire [3:0]  host_pop_be;
    wire        host_pop_empty;

    integer errors;

    ft601_bus_model #(.DEPTH(1024)) u_chip (
        .clk(clk), .rst(rst_chip),
        .ft_data(ft_data), .ft_be(ft_be),
        .ft_rxf(ft_rxf), .ft_txe(ft_txe),
        .ft_oe(ft_oe), .ft_rd(ft_rd), .ft_wr(ft_wr),
        .host_push_en(host_push_en), .host_push_data(host_push_data),
        .host_push_be(4'hF), .host_push_full(host_push_full),
        .host_pop_en(host_pop_en), .host_pop_data(host_pop_data),
        .host_pop_be(host_pop_be), .host_pop_empty(host_pop_empty)
    );

    la_capture_core #(
        .SAMPLE_MHZ     (100),
        .DEFAULT_SOURCE (2'd0),
        .BUF_DEPTH      (BUF_DEPTH),
        .DEFAULT_POST   (16),
        .DEFAULT_CH     (3'd0),
        .DEFAULT_EDGE   (2'd0)
    ) u_dut (
        .ft_clk(clk), .rst(rst_dut), .la_in(8'd0),
        .ft_data(ft_data), .ft_be(ft_be),
        .ft_rxf(ft_rxf), .ft_txe(ft_txe),
        .ft_oe(ft_oe), .ft_rd(ft_rd), .ft_wr(ft_wr),
        .overflow_sticky(), .fifo_empty(), .fifo_full(), .tx_active(),
        .source_sel(), .armed(), .triggered(), .cap_done(),
        .overflow_cnt(), .drop_cnt(), .ddr3_word_count()
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function [31:0] mk_cmd;
        input [3:0]  cmd;
        input [1:0]  src;
        input [2:0]  ch;
        input [1:0]  e_mode;
        input [15:0] post;
        begin
            mk_cmd = {post, 5'd0, e_mode, ch, src, cmd};
        end
    endfunction

    task reset_dut;
        begin
            rst_dut = 1'b1;
            host_push_en = 1'b0;
            host_pop_en = 1'b0;
            repeat (4) @(posedge clk);
            rst_dut = 1'b0;
            repeat (8) @(posedge clk);
        end
    endtask

    task push_cmd;
        input [31:0] word;
        begin
            @(posedge clk);
            host_push_en   <= 1'b1;
            host_push_data <= word;
            @(posedge clk);
            host_push_en <= 1'b0;
        end
    endtask

    task pop_word;
        output [31:0] data;
        integer t;
        begin
            t = 0;
            data = 32'hdeadbeef;
            host_pop_en = 1'b0;
            while (t < 4000) begin
                @(posedge clk);
                host_pop_en <= 1'b0;
                t = t + 1;
                #1;
                if (!host_pop_empty) begin
                    data = host_pop_data;
                    @(posedge clk);
                    host_pop_en <= 1'b1;
                    @(posedge clk);
                    host_pop_en <= 1'b0;
                    t = 4000;
                end
            end
            if (data === 32'hdeadbeef) begin
                $display("TIMEOUT waiting for TX word");
                errors = errors + 1;
            end
        end
    endtask

    task drain_dump;
        output integer nsamp;
        output integer tpos;
        output integer status;
        output integer ovf;
        output integer drop;
        integer i, nwords;
        reg [31:0] hdr [0:7];
        reg [31:0] junk;
        begin
            for (i = 0; i < HDR_WORDS; i = i + 1)
                pop_word(hdr[i]);
            if (hdr[0] !== MAGIC) begin
                $display("bad MAGIC %h", hdr[0]);
                errors = errors + 1;
            end
            status = hdr[2];
            nsamp  = hdr[3];
            tpos   = hdr[4];
            ovf    = hdr[5];
            drop   = hdr[6];
            nwords = (nsamp + 3) / 4;
            for (i = 0; i < nwords; i = i + 1)
                pop_word(junk);
        end
    endtask

    integer ns, tp, st, ov, dr;

    initial begin
        errors = 0;
        rst_chip = 1'b1;
        rst_dut = 1'b1;
        host_push_en = 1'b0;
        host_push_data = 32'd0;
        host_pop_en = 1'b0;
        repeat (4) @(posedge clk);
        rst_chip = 1'b0;
        repeat (2) @(posedge clk);

        // 1. Falling edge on counter ch0: 1→0 at sample 2.
        reset_dut();
        push_cmd(mk_cmd(CMD_START, 2'd0, 3'd0, 2'd1, 16'd8));
        drain_dump(ns, tp, st, ov, dr);
        if (!st[8] || tp !== 2) begin
            $display("fall: triggered=%0d tpos=%0d (exp 2)", st[8], tp);
            errors = errors + 1;
        end else
            $display("  fall tpos=%0d nsamp=%0d", tp, ns);

        // 2. Both edges: first edge is the rise at sample 1.
        reset_dut();
        push_cmd(mk_cmd(CMD_START, 2'd0, 3'd0, 2'd2, 16'd8));
        drain_dump(ns, tp, st, ov, dr);
        if (!st[8] || tp !== 1) begin
            $display("both: triggered=%0d tpos=%0d (exp 1)", st[8], tp);
            errors = errors + 1;
        end else
            $display("  both tpos=%0d nsamp=%0d", tp, ns);

        // 3. Channel 3: counter bit 3 rises at sample 8.
        reset_dut();
        push_cmd(mk_cmd(CMD_START, 2'd0, 3'd3, 2'd0, 16'd8));
        drain_dump(ns, tp, st, ov, dr);
        if (!st[8] || tp !== 8) begin
            $display("ch3: triggered=%0d tpos=%0d (exp 8)", st[8], tp);
            errors = errors + 1;
        end else
            $display("  ch3 tpos=%0d nsamp=%0d", tp, ns);

        // 4. Immediate: trigger on first stored sample, tpos=0.
        reset_dut();
        push_cmd(mk_cmd(CMD_START, 2'd0, 3'd0, 2'd3, 16'd8));
        drain_dump(ns, tp, st, ov, dr);
        if (!st[8] || tp !== 0) begin
            $display("imm: triggered=%0d tpos=%0d (exp 0) status=%h", st[8], tp, st);
            errors = errors + 1;
        end else
            $display("  imm tpos=%0d nsamp=%0d immbit=%0d", tp, ns, st[11]);

        // 5. STOP before trigger: watch ch7 (first rise at 128, BUF=32).
        reset_dut();
        push_cmd(mk_cmd(CMD_START, 2'd0, 3'd7, 2'd0, 16'd8));
        repeat (40) @(posedge clk);
        push_cmd(mk_cmd(CMD_STOP, 2'd0, 3'd7, 2'd0, 16'd0));
        drain_dump(ns, tp, st, ov, dr);
        if (st[8] !== 1'b0 || tp !== 32'hffffffff || st[10] !== 1'b1) begin
            $display("stop: trig=%0d tpos=%h aborted=%0d drop=%0d nsamp=%0d",
                     st[8], tp, st[10], dr, ns);
            errors = errors + 1;
        end else if (dr == 0) begin
            $display("stop: drop_cnt should be remaining post, got 0");
            errors = errors + 1;
        end else
            $display("  stop aborted nsamp=%0d drop=%0d", ns, dr);

        // 6. Overflow: immediate + post larger than BUF_DEPTH.
        reset_dut();
        push_cmd(mk_cmd(CMD_START, 2'd0, 3'd0, 2'd3, 16'd64));
        drain_dump(ns, tp, st, ov, dr);
        if (!st[8] || ns > BUF_DEPTH) begin
            $display("ovf: nsamp=%0d > depth? trig=%0d", ns, st[8]);
            errors = errors + 1;
        end else if (ov == 0 && dr == 0) begin
            $display("ovf: expected overflow or drop, ov=%0d drop=%0d nsamp=%0d",
                     ov, dr, ns);
            errors = errors + 1;
        end else
            $display("  overflow/drop ov=%0d drop=%0d nsamp=%0d tpos=%0d",
                     ov, dr, ns, tp);

        // 7. FORCE while waiting for ch7.
        reset_dut();
        push_cmd(mk_cmd(CMD_START, 2'd0, 3'd7, 2'd0, 16'd8));
        repeat (20) @(posedge clk);
        push_cmd(mk_cmd(CMD_FORCE, 2'd0, 3'd7, 2'd0, 16'd0));
        drain_dump(ns, tp, st, ov, dr);
        if (!st[8]) begin
            $display("force: did not trigger nsamp=%0d tpos=%h", ns, tp);
            errors = errors + 1;
        end else
            $display("  force tpos=%0d nsamp=%0d", tp, ns);

        if (errors == 0) begin
            $display("PASS: trigger fall/both/ch3/imm/stop/overflow/force");
            $finish;
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $finish(1);
        end
    end

endmodule
