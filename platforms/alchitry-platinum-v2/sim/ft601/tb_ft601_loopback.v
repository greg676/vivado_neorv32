`timescale 1ns / 1ps
module tb_ft601_loopback;

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
    reg  [3:0]  host_push_be;
    wire        host_push_full;
    reg         host_pop_en;
    wire [31:0] host_pop_data;
    wire [3:0]  host_pop_be;
    wire        host_pop_empty;

    integer     i;
    integer     got;
    integer     errors;
    integer     timeout;
    ft601_bus_model u_chip (
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
        .host_push_be   (host_push_be),
        .host_push_full (host_push_full),
        .host_pop_en    (host_pop_en),
        .host_pop_data  (host_pop_data),
        .host_pop_be    (host_pop_be),
        .host_pop_empty (host_pop_empty)
    );

    ft601_loopback_core #(
        .MODE("LOOPBACK")
    ) u_dut (
        .ft_clk          (clk),
        .rst             (rst_dut),
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
        .rx_active       (),
        .tx_active       ()
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst_chip       = 1'b1;
        rst_dut        = 1'b1;
        host_push_en   = 1'b0;
        host_push_data = 32'd0;
        host_push_be   = 4'hF;
        host_pop_en    = 1'b0;
        errors         = 0;
        got            = 0;
        repeat (4) @(posedge clk);
        rst_chip = 1'b0;
        repeat (2) @(posedge clk);

        // Load the FT601 RX queue while the FPGA is held in reset.
        for (i = 0; i < 64; i = i + 1) begin
            @(posedge clk);
            host_push_en   <= 1'b1;
            host_push_data <= i[31:0];
            host_push_be   <= 4'hF;
        end
        @(posedge clk);
        host_push_en <= 1'b0;
        repeat (2) @(posedge clk);

        rst_dut = 1'b0;

        timeout = 0;
        while (got < 64 && timeout < 20000) begin
            @(posedge clk);
            host_pop_en <= 1'b0;
            timeout = timeout + 1;
            #1;
            if (!host_pop_empty) begin
                if (host_pop_data !== got[31:0]) begin
                    $display("MISMATCH word %0d: got %h expected %h",
                             got, host_pop_data, got[31:0]);
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

        if (got != 64) begin
            $display("TIMEOUT: only received %0d / 64 words", got);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: 64/64 words looped, BE=0xF, no drops");
            $finish;
        end else begin
            $display("FAIL: %0d error(s), received %0d", errors, got);
            $finish(1);
        end
    end

endmodule
