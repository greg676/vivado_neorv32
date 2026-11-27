`timescale 1ns / 1ps
// Packer-only: known pattern bytes become little-endian FT601 words.
module tb_la_packer;

    reg         clk;
    reg         rst;
    integer     errors;
    integer     words_got;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ── 100 MS/s counter ──────────────────────────────────────
    wire [7:0]  p100_s0, p100_s1;
    wire [31:0] w100;
    wire        v100;

    la_pattern #(.SAMPLE_MHZ(100)) u_pat100 (
        .clk(clk), .rst(rst), .source(2'd0), .s0(p100_s0), .s1(p100_s1)
    );
    la_packer #(.SAMPLE_MHZ(100)) u_pack100 (
        .clk(clk), .rst(rst), .enable(1'b1),
        .s0(p100_s0), .s1(p100_s1), .out_data(w100), .out_valid(v100)
    );

    // ── 200 MS/s counter ──────────────────────────────────────
    wire [7:0]  p200_s0, p200_s1;
    wire [31:0] w200;
    wire        v200;

    la_pattern #(.SAMPLE_MHZ(200)) u_pat200 (
        .clk(clk), .rst(rst), .source(2'd0), .s0(p200_s0), .s1(p200_s1)
    );
    la_packer #(.SAMPLE_MHZ(200)) u_pack200 (
        .clk(clk), .rst(rst), .enable(1'b1),
        .s0(p200_s0), .s1(p200_s1), .out_data(w200), .out_valid(v200)
    );

    // ── 100 MS/s walking ──────────────────────────────────────
    wire [7:0]  pw_s0, pw_s1;
    wire [31:0] ww;
    wire        vw;

    la_pattern #(.SAMPLE_MHZ(100)) u_patw (
        .clk(clk), .rst(rst), .source(2'd1), .s0(pw_s0), .s1(pw_s1)
    );
    la_packer #(.SAMPLE_MHZ(100)) u_packw (
        .clk(clk), .rst(rst), .enable(1'b1),
        .s0(pw_s0), .s1(pw_s1), .out_data(ww), .out_valid(vw)
    );

    integer idx100, idx200, idxw;
    integer expect_word;
    integer s0, s1, s2, s3;

    function [31:0] pack4;
        input [7:0] a, b, c, d;
        begin
            pack4 = {d, c, b, a};
        end
    endfunction

    initial begin
        rst = 1'b1;
        errors = 0;
        idx100 = 0;
        idx200 = 0;
        idxw = 0;
        words_got = 0;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        repeat (512) begin
            @(posedge clk);
            #1;
            if (v100) begin
                s0 = (idx100 * 4 + 0) & 8'hFF;
                s1 = (idx100 * 4 + 1) & 8'hFF;
                s2 = (idx100 * 4 + 2) & 8'hFF;
                s3 = (idx100 * 4 + 3) & 8'hFF;
                expect_word = pack4(s0[7:0], s1[7:0], s2[7:0], s3[7:0]);
                if (w100 !== expect_word[31:0]) begin
                    $display("100MS pack mismatch word %0d: got %h exp %h",
                             idx100, w100, expect_word[31:0]);
                    errors = errors + 1;
                end
                idx100 = idx100 + 1;
            end
            if (v200) begin
                s0 = (idx200 * 4 + 0) & 8'hFF;
                s1 = (idx200 * 4 + 1) & 8'hFF;
                s2 = (idx200 * 4 + 2) & 8'hFF;
                s3 = (idx200 * 4 + 3) & 8'hFF;
                expect_word = pack4(s0[7:0], s1[7:0], s2[7:0], s3[7:0]);
                if (w200 !== expect_word[31:0]) begin
                    $display("200MS pack mismatch word %0d: got %h exp %h",
                             idx200, w200, expect_word[31:0]);
                    errors = errors + 1;
                end
                idx200 = idx200 + 1;
            end
            if (vw) begin
                s0 = 8'd1 << ((idxw * 4 + 0) % 8);
                s1 = 8'd1 << ((idxw * 4 + 1) % 8);
                s2 = 8'd1 << ((idxw * 4 + 2) % 8);
                s3 = 8'd1 << ((idxw * 4 + 3) % 8);
                expect_word = pack4(s0[7:0], s1[7:0], s2[7:0], s3[7:0]);
                if (ww !== expect_word[31:0]) begin
                    $display("walk pack mismatch word %0d: got %h exp %h",
                             idxw, ww, expect_word[31:0]);
                    errors = errors + 1;
                end
                idxw = idxw + 1;
            end
        end

        if (idx100 < 64) begin
            $display("100MS: only %0d words (need >= 64)", idx100);
            errors = errors + 1;
        end
        if (idx200 < 64) begin
            $display("200MS: only %0d words (need >= 64)", idx200);
            errors = errors + 1;
        end
        if (idxw < 16) begin
            $display("walk: only %0d words (need >= 16)", idxw);
            errors = errors + 1;
        end

        words_got = idx100 + idx200 + idxw;
        if (errors == 0) begin
            $display("PASS: packer 100MS words=%0d 200MS words=%0d walk words=%0d",
                     idx100, idx200, idxw);
            $finish;
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $finish(1);
        end
    end

endmodule
