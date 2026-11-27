`timescale 1ns / 1ps
// Self-checking pack of la_pattern (counter + walking). No FT601 model.
module tb_la_pattern;
    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        enable = 1'b0;
    wire [7:0] c0, c1, c2, c3;
    wire [7:0] w0, w1, w2, w3;
    integer    i;
    integer    errors = 0;

    la_pattern #(.SOURCE(2'd0)) u_ctr (
        .clk(clk), .rst(rst), .enable(enable),
        .s0(c0), .s1(c1), .s2(c2), .s3(c3)
    );
    la_pattern #(.SOURCE(2'd1)) u_walk (
        .clk(clk), .rst(rst), .enable(enable),
        .s0(w0), .s1(w1), .s2(w2), .s3(w3)
    );

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
        if ({c3, c2, c1, c0} !== 32'h03020100) begin
            $display("FAIL reset counter 0x%08x", {c3, c2, c1, c0});
            errors = errors + 1;
        end
        if ({w3, w2, w1, w0} !== 32'h08040201) begin
            $display("FAIL reset walking 0x%08x", {w3, w2, w1, w0});
            errors = errors + 1;
        end
        enable <= 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            if (c0 !== (i * 4)     || c1 !== (i * 4 + 1) ||
                c2 !== (i * 4 + 2) || c3 !== (i * 4 + 3)) begin
                $display("FAIL counter i=%0d %02x %02x %02x %02x",
                         i, c0, c1, c2, c3);
                errors = errors + 1;
            end
        end
        if (errors == 0)
            $display("PASS tb_la_pattern");
        else
            $display("FAIL tb_la_pattern errors=%0d", errors);
        $finish;
    end
endmodule
