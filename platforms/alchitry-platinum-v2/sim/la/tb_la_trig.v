// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Combinational edge detector on one of 8 channels.
module tb_la_trig;

    reg        clk;
    reg        rst;
    reg        enable;
    reg [7:0]  s0;
    reg [7:0]  s1;
    reg [2:0]  channel;
    reg [1:0]  edge_mode;
    wire       hit100, hit100_s1;
    wire       hit200, hit200_s1;

    integer errors;

    la_trig #(.SAMPLE_MHZ(100)) u100 (
        .clk(clk), .rst(rst), .enable(enable),
        .s0(s0), .s1(s1), .channel(channel), .edge_mode(edge_mode),
        .hit(hit100), .hit_s1(hit100_s1)
    );
    la_trig #(.SAMPLE_MHZ(200)) u200 (
        .clk(clk), .rst(rst), .enable(enable),
        .s0(s0), .s1(s1), .channel(channel), .edge_mode(edge_mode),
        .hit(hit200), .hit_s1(hit200_s1)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task fail;
        input [255:0] msg;
        begin
            $display("FAIL: %0s  s0=%h s1=%h ch=%0d edge=%0d hit100=%b/%b hit200=%b/%b prev100=%b hp100=%b",
                     msg, s0, s1, channel, edge_mode,
                     hit100, hit100_s1, hit200, hit200_s1,
                     u100.prev, u100.have_prev);
            errors = errors + 1;
        end
    endtask

    task settle;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst = 1'b1;
        enable = 1'b0;
        s0 = 8'd0;
        s1 = 8'd0;
        channel = 3'd0;
        edge_mode = 2'd0;
        errors = 0;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // Establish prev=0 on ch0.
        enable = 1'b1;
        s0 = 8'h00;
        s1 = 8'h00;
        edge_mode = 2'd0;
        settle();
        if (hit100 || hit200) fail("first sample must not edge-trigger");

        // Rising on ch0.
        s0 = 8'h01;
        s1 = 8'h00;
        #1;
        if (!hit100) fail("100 rise ch0");
        if (hit100_s1) fail("100 hit_s1 must be 0");
        if (!hit200) fail("200 rise on s0");
        if (hit200_s1) fail("200 rise on s0 is not s1");
        settle();

        // Stay high so prev=1, then fall.
        s0 = 8'h01;
        s1 = 8'h01;
        edge_mode = 2'd1;
        settle();
        s0 = 8'h00;
        s1 = 8'h00;
        #1;
        if (!hit100) fail("100 fall ch0");
        if (!hit200) fail("200 fall s0");
        if (hit200_s1) fail("200 fall s0 is not s1");
        settle();

        // Both: rise again. prev is 0 after the fall clock.
        edge_mode = 2'd2;
        s0 = 8'h01;
        s1 = 8'h00;
        #1;
        if (!hit100 || !hit200) fail("both-edge rise");
        settle();

        // Channel 3 only.
        edge_mode = 2'd0;
        channel = 3'd3;
        s0 = 8'h00;
        s1 = 8'h00;
        settle();
        s0 = 8'h08;
        #1;
        if (!hit100) fail("rise ch3");
        settle();
        s0 = 8'h09; // ch0 also 1; ch3 stays high so no new edge
        #1;
        if (hit100) fail("no extra hit while ch3 stays 1");
        settle();

        // 200 MS/s: rise on s1 only (prev=1, s0=0, s1=1).
        channel = 3'd0;
        edge_mode = 2'd0;
        s0 = 8'h01;
        s1 = 8'h01;
        settle();
        s0 = 8'h00;
        s1 = 8'h01;
        #1;
        if (hit100) fail("100 should see 1→0, not a rise");
        if (!hit200) fail("200 should rise on s1");
        if (!hit200_s1) fail("200 rise must flag hit_s1");
        settle();

        // Immediate: first enabled sample.
        enable = 1'b0;
        settle();
        edge_mode = 2'd3;
        s0 = 8'h00;
        s1 = 8'h00;
        enable = 1'b1;
        #1;
        if (!hit100 || !hit200) fail("immediate");
        if (hit200_s1) fail("immediate is s0");

        if (errors == 0) begin
            $display("PASS: la_trig rise/fall/both/imm + ch select + 200 s1");
            $finish;
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $finish(1);
        end
    end

endmodule
