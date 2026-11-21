`timescale 1ns / 1ps
// Capture core: START, edge trigger, header with trigger position, packed payload.
`ifndef SAMPLE_MHZ
`define SAMPLE_MHZ 100
`endif
`ifndef SRC_SEL
`define SRC_SEL 0
`endif

module tb_la_capture;

    localparam integer SAMPLE_MHZ = `SAMPLE_MHZ;
    localparam integer SRC_SEL    = `SRC_SEL;
    localparam integer BUF_DEPTH  = 128;
    localparam integer POST_N     = 64;
    localparam integer HDR_WORDS  = 8;
    localparam [31:0]  MAGIC      = 32'h3354414C;

    localparam [3:0] CMD_START = 4'd2;

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

    integer     errors;
    integer     timeout;
    integer     i;
    integer     nsamp;
    integer     tpos;
    integer     status;
    integer     nwords;
    integer     s0, s1, s2, s3;
    integer     expect_word;
    integer     sample_base;
    integer     got_payload;
    integer     exp_tpos;
    reg [31:0]  hdr [0:7];
    reg [31:0]  word;

    ft601_bus_model #(
        .DEPTH(512)
    ) u_chip (
        .clk            (clk),
        .rst            (rst_chip),
        .ft_data        (ft_data),
        .ft_be          (ft_be),
        .ft_rxf         (ft_rxf),
        .ft_txe         (ft_txe),
        .ft_oe          (ft_oe),
        .ft_rd          (ft_rd),
        .ft_wr          (ft_wr),
        .host_push_en   (host_push_en),
        .host_push_data (host_push_data),
        .host_push_be   (4'hF),
        .host_push_full (host_push_full),
        .host_pop_en    (host_pop_en),
        .host_pop_data  (host_pop_data),
        .host_pop_be    (host_pop_be),
        .host_pop_empty (host_pop_empty)
    );

    la_capture_core #(
        .SAMPLE_MHZ     (SAMPLE_MHZ),
        .DEFAULT_SOURCE (SRC_SEL[1:0]),
        .BUF_DEPTH      (BUF_DEPTH),
        .DEFAULT_POST   (POST_N),
        .DEFAULT_CH     (3'd0),
        .DEFAULT_EDGE   (2'd0)
    ) u_dut (
        .ft_clk          (clk),
        .rst             (rst_dut),
        .la_in           (8'd0),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf          (ft_rxf),
        .ft_txe          (ft_txe),
        .ft_oe           (ft_oe),
        .ft_rd           (ft_rd),
        .ft_wr           (ft_wr),
        .overflow_sticky (),
        .fifo_empty      (),
        .fifo_full       (),
        .tx_active       (),
        .source_sel      (),
        .armed           (),
        .triggered       (),
        .cap_done        (),
        .overflow_cnt    (),
        .drop_cnt        (),
        .ddr3_word_count ()
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

    function [7:0] sample_at;
        input integer idx;
        begin
            if (SRC_SEL == 1)
                sample_at = 8'd1 << (idx[2:0]);
            else
                sample_at = idx[7:0];
        end
    endfunction

    function [31:0] pack4;
        input [7:0] a, b, c, d;
        begin
            pack4 = {d, c, b, a};
        end
    endfunction

    task pop_word;
        output [31:0] data;
        integer t;
        begin
            t = 0;
            data = 32'hdeadbeef;
            host_pop_en = 1'b0;
            while (t < 20000) begin
                @(posedge clk);
                host_pop_en <= 1'b0;
                t = t + 1;
                #1;
                if (!host_pop_empty) begin
                    if (host_pop_be !== 4'hF) begin
                        $display("BE error: be=%h", host_pop_be);
                        errors = errors + 1;
                    end
                    data = host_pop_data;
                    @(posedge clk);
                    host_pop_en <= 1'b1;
                    @(posedge clk);
                    host_pop_en <= 1'b0;
                    t = 20000;
                end
            end
            if (data === 32'hdeadbeef) begin
                $display("TIMEOUT waiting for TX word");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        rst_chip       = 1'b1;
        rst_dut        = 1'b1;
        host_push_en   = 1'b0;
        host_push_data = 32'd0;
        host_pop_en    = 1'b0;
        errors         = 0;
        repeat (4) @(posedge clk);
        rst_chip = 1'b0;
        repeat (2) @(posedge clk);
        rst_dut = 1'b0;
        repeat (8) @(posedge clk);

        // START: source, ch0, rising, post=64.
        @(posedge clk);
        host_push_en   <= 1'b1;
        host_push_data <= mk_cmd(CMD_START, SRC_SEL[1:0], 3'd0, 2'd0, POST_N[15:0]);
        @(posedge clk);
        host_push_en <= 1'b0;

        for (i = 0; i < HDR_WORDS; i = i + 1)
            pop_word(hdr[i]);

        if (hdr[0] !== MAGIC) begin
            $display("MAGIC got %h", hdr[0]);
            errors = errors + 1;
        end
        if (hdr[1] !== 32'd1) begin
            $display("VERSION got %h", hdr[1]);
            errors = errors + 1;
        end
        status = hdr[2];
        nsamp  = hdr[3];
        tpos   = hdr[4];
        if (status[8] !== 1'b1) begin
            $display("STATUS triggered bit clear: %h", hdr[2]);
            errors = errors + 1;
        end
        if (status[1:0] !== SRC_SEL[1:0]) begin
            $display("STATUS source %0d expected %0d", status[1:0], SRC_SEL);
            errors = errors + 1;
        end
        if (hdr[7][15:0] !== POST_N[15:0]) begin
            $display("POST_CFG %0d expected %0d", hdr[7][15:0], POST_N);
            errors = errors + 1;
        end

        if (SRC_SEL == 1)
            exp_tpos = 8;
        else if (SAMPLE_MHZ == 200)
            exp_tpos = 3;
        else
            exp_tpos = 1;

        if (tpos !== exp_tpos) begin
            $display("TRIG_POS %0d expected %0d", tpos, exp_tpos);
            errors = errors + 1;
        end
        if (nsamp < (exp_tpos + 1 + POST_N - 2) || nsamp > (exp_tpos + 1 + POST_N + 2)) begin
            $display("NSAMPLES %0d out of range around trig=%0d post=%0d",
                     nsamp, exp_tpos, POST_N);
            errors = errors + 1;
        end

        nwords = (nsamp + 3) / 4;
        got_payload = 0;
        for (i = 0; i < nwords; i = i + 1) begin
            pop_word(word);
            sample_base = i * 4;
            s0 = sample_at(sample_base + 0);
            s1 = sample_at(sample_base + 1);
            s2 = sample_at(sample_base + 2);
            s3 = sample_at(sample_base + 3);
            if (sample_base + 0 >= nsamp) s0 = 0;
            if (sample_base + 1 >= nsamp) s1 = 0;
            if (sample_base + 2 >= nsamp) s2 = 0;
            if (sample_base + 3 >= nsamp) s3 = 0;
            expect_word = pack4(s0[7:0], s1[7:0], s2[7:0], s3[7:0]);
            if (word !== expect_word[31:0]) begin
                $display("PAYLOAD word %0d: got %h expected %h",
                         i, word, expect_word[31:0]);
                errors = errors + 1;
            end
            got_payload = got_payload + 1;
        end

        if (errors == 0) begin
            $display("PASS: trigger dump SAMPLE_MHZ=%0d SRC=%0d nsamp=%0d tpos=%0d words=%0d",
                     SAMPLE_MHZ, SRC_SEL, nsamp, tpos, got_payload);
            $finish;
        end else begin
            $display("FAIL: %0d error(s) SAMPLE_MHZ=%0d SRC=%0d nsamp=%0d tpos=%0d",
                     errors, SAMPLE_MHZ, SRC_SEL, nsamp, tpos);
            $finish(1);
        end
    end

endmodule
