`timescale 1ns / 1ps
// Capture core through the FT601 245 model: packed 8-bit samples appear
// as 32-bit TX words with BE=0xF.
`ifndef SAMPLE_MHZ
`define SAMPLE_MHZ 100
`endif
`ifndef SRC_SEL
`define SRC_SEL 0
`endif

module tb_la_capture;

    localparam integer SAMPLE_MHZ = `SAMPLE_MHZ;
    localparam integer SRC_SEL    = `SRC_SEL;
    localparam integer NSAMPLES   = 256;
    localparam integer NWORDS     = NSAMPLES / 4;

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

    integer     got;
    integer     errors;
    integer     timeout;
    integer     s0, s1, s2, s3;
    integer     expect_word;
    integer     sample_base;

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
        .DEFAULT_SOURCE (SRC_SEL[1:0])
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
        .ddr3_word_count ()
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

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

    initial begin
        rst_chip       = 1'b1;
        rst_dut        = 1'b1;
        host_push_en   = 1'b0;
        host_push_data = 32'd0;
        host_pop_en    = 1'b0;
        errors         = 0;
        got            = 0;
        repeat (4) @(posedge clk);
        rst_chip = 1'b0;
        repeat (2) @(posedge clk);
        rst_dut = 1'b0;

        timeout = 0;
        while (got < NWORDS && timeout < 20000) begin
            @(posedge clk);
            host_pop_en <= 1'b0;
            timeout = timeout + 1;
            #1;
            if (!host_pop_empty) begin
                sample_base = got * 4;
                s0 = sample_at(sample_base + 0);
                s1 = sample_at(sample_base + 1);
                s2 = sample_at(sample_base + 2);
                s3 = sample_at(sample_base + 3);
                expect_word = pack4(s0[7:0], s1[7:0], s2[7:0], s3[7:0]);
                if (host_pop_data !== expect_word[31:0]) begin
                    $display("MISMATCH word %0d: got %h expected %h (samples %0d..)",
                             got, host_pop_data, expect_word[31:0], sample_base);
                    errors = errors + 1;
                end
                if (host_pop_be !== 4'hF) begin
                    $display("BE error word %0d: be=%h", got, host_pop_be);
                    errors = errors + 1;
                end
                @(posedge clk);
                host_pop_en <= 1'b1;
                @(posedge clk);
                host_pop_en <= 1'b0;
                got = got + 1;
            end
        end

        if (got != NWORDS) begin
            $display("TIMEOUT: only received %0d / %0d words", got, NWORDS);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: %0d/%0d TX words SAMPLE_MHZ=%0d SRC=%0d BE=0xF",
                     got, NWORDS, SAMPLE_MHZ, SRC_SEL);
            $finish;
        end else begin
            $display("FAIL: %0d error(s), received %0d  SAMPLE_MHZ=%0d SRC=%0d",
                     errors, got, SAMPLE_MHZ, SRC_SEL);
            $finish(1);
        end
    end

endmodule
