`timescale 1ns / 1ps
// 245 FT601 loopback sim: PHY-like RXF/TXE, pad timing, host-reusable vectors.
module tb_ft601_loopback;

    reg         clk;
    reg         clk_board;
    reg         rst_n_btn;
    reg         rst_phy;
    wire        ft_reset;
    wire        rst_ft;

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

    integer     errors;
    integer     timing_v;
    integer     i;
    integer     got;
    integer     timeout;
    integer     fd;
    integer     nvec;
    reg  [31:0] vec [0:255];
    reg  [31:0] echo [0:255];
    reg  [3:0]  echo_be [0:255];

    ft601_reset u_reset (
        .clk_board   (clk_board),
        .rst_n_async (rst_n_btn),
        .ft_clk      (clk),
        .ft_reset    (ft_reset),
        .rst_ft      (rst_ft)
    );

    ft601_phy_245 #(
        .DEPTH(64)
    ) u_phy (
        .clk            (clk),
        .rst            (rst_phy),
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
        .rst             (rst_ft),
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

    ft601_245_monitor u_mon (
        .clk          (clk),
        .rst          (rst_ft),
        .ft_data      (ft_data),
        .ft_be        (ft_be),
        .ft_rxf       (ft_rxf),
        .ft_txe       (ft_txe),
        .ft_oe        (ft_oe),
        .ft_rd        (ft_rd),
        .ft_wr        (ft_wr),
        .fpga_driving (u_dut.u_phy.data_oe_r),
        .violations   (timing_v)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;           // 100 MHz FT601 CLK
    initial clk_board = 1'b0;
    always #5 clk_board = ~clk_board;

    task automatic host_push_word;
        input [31:0] data;
        input [3:0]  be;
        begin
            @(posedge clk);
            while (host_push_full) @(posedge clk);
            host_push_en   <= 1'b1;
            host_push_data <= data;
            host_push_be   <= be;
            @(posedge clk);
            host_push_en <= 1'b0;
        end
    endtask

    task automatic host_pop_word;
        output [31:0] data;
        output [3:0]  be;
        integer t;
        begin
            t = 0;
            while (host_pop_empty && t < 20000) begin
                @(posedge clk);
                #1;
                t = t + 1;
            end
            #1;
            if (host_pop_empty) begin
                $display("TIMEOUT waiting for TX FIFO word");
                errors = errors + 1;
                data = 32'hxxxxxxxx;
                be   = 4'hx;
            end else begin
                data = host_pop_data;
                be   = host_pop_be;
                @(posedge clk);
                host_pop_en <= 1'b1;
                @(posedge clk);
                host_pop_en <= 1'b0;
            end
        end
    endtask

    task automatic load_hex;
        input [8*128-1:0] path;
        integer h, rc, idx;
        reg [31:0] w;
        begin
            h = $fopen(path, "r");
            if (h == 0) begin
                $display("FAIL: cannot open %0s", path);
                $finish(1);
            end
            idx = 0;
            rc = $fscanf(h, "%h", w);
            while (rc == 1 && idx < 256) begin
                vec[idx] = w;
                idx = idx + 1;
                rc = $fscanf(h, "%h", w);
            end
            $fclose(h);
            nvec = idx;
            $display("Loaded %0d words from %0s", nvec, path);
        end
    endtask

    task automatic dump_bin;
        input [8*128-1:0] path;
        integer h, k;
        begin
            h = $fopen(path, "wb");
            if (h == 0) begin
                $display("FAIL: cannot write %0s", path);
                errors = errors + 1;
            end else begin
                for (k = 0; k < nvec; k = k + 1)
                    $fwrite(h, "%u", echo[k]);
                $fclose(h);
                $display("Wrote echo vector %0s (%0d words, LE)", path, nvec);
            end
        end
    endtask

    task automatic hold_fpga_reset;
        input hold;
        integer t;
        begin
            rst_n_btn = hold ? 1'b0 : 1'b1;
            t = 0;
            if (hold) begin
                while (rst_ft !== 1'b1 && t < 20) begin
                    @(posedge clk);
                    t = t + 1;
                end
            end else begin
                while (rst_ft !== 1'b0 && t < 20) begin
                    @(posedge clk);
                    t = t + 1;
                end
            end
        end
    endtask

    task automatic run_vector_rx_be;
        input [3:0] rx_be;
        input [3:0] expect_tx_be;
        integer k;
        reg [31:0] d;
        reg [3:0]  b;
        begin
            got = 0;
            hold_fpga_reset(1);
            for (k = 0; k < nvec; k = k + 1)
                host_push_word(vec[k], rx_be);
            hold_fpga_reset(0);

            for (k = 0; k < nvec; k = k + 1) begin
                host_pop_word(d, b);
                echo[k]    = d;
                echo_be[k] = b;
                if (d !== vec[k]) begin
                    $display("MISMATCH word %0d: got %h expected %h", k, d, vec[k]);
                    errors = errors + 1;
                end
                if (b !== expect_tx_be) begin
                    $display("BE error word %0d: be=%h expected TX %h", k, b, expect_tx_be);
                    errors = errors + 1;
                end
                got = got + 1;
            end
        end
    endtask

    task automatic run_vector;
        input [3:0] be_force;
        begin
            run_vector_rx_be(be_force, 4'hF);
        end
    endtask

    initial begin
        errors         = 0;
        host_push_en   = 1'b0;
        host_push_data = 32'd0;
        host_push_be   = 4'hF;
        host_pop_en    = 1'b0;
        rst_n_btn      = 1'b1;
        rst_phy        = 1'b1;
        nvec           = 0;

        if ($test$plusargs("vcd")) begin
            $dumpfile("tb_ft601_loopback.vcd");
            $dumpvars(0, tb_ft601_loopback);
        end

        repeat (4) @(posedge clk);
        rst_phy = 1'b0;
        // RESET_N must already be high after DONE (no 1 ms pulse).
        repeat (20) @(posedge clk);
        if (ft_reset !== 1'b1) begin
            $display("FAIL: ft_reset=%b after DONE, expected 1", ft_reset);
            errors = errors + 1;
        end
        timeout = 0;
        while (rst_ft !== 1'b0 && timeout < 20) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (rst_ft !== 1'b0) begin
            $display("FAIL: rst_ft stuck asserted with button up");
            errors = errors + 1;
        end else
            $display("PASS reset: ft_reset=1, rst_ft released in %0d ft_clk", timeout);

        load_hex("vectors/counter.hex");
        run_vector(4'hF);
        dump_bin("vectors/sim_echo.bin");
        $display("PASS counter: %0d/%0d words, BE=0xF", got, nvec);

        load_hex("vectors/walking.hex");
        run_vector(4'hF);
        $display("PASS walking: %0d/%0d words", got, nvec);

        load_hex("vectors/xor.hex");
        run_vector(4'hF);
        $display("PASS xor: %0d/%0d words", got, nvec);

        // Host USB is always 4-byte words. Push with BE=0x3 (only DATA[15:0]
        // marked valid on the pad); echo TX must still drive BE=0xF so the
        // host does not drop bytes 2/3.
        nvec = 8;
        for (i = 0; i < 8; i = i + 1)
            vec[i] = 32'hA5A50000 + i[31:0];
        run_vector_rx_be(4'h3, 4'hF);
        $display("PASS BE pad 0x3 -> TX 0xF: %0d words", got);

        // TXE backpressure: stop popping until PHY TX fills, then drain.
        nvec = 64;
        for (i = 0; i < 64; i = i + 1)
            vec[i] = 32'hBEEF0000 + i[31:0];
        hold_fpga_reset(1);
        for (i = 0; i < 64; i = i + 1)
            host_push_word(vec[i], 4'hF);
        hold_fpga_reset(0);
        timeout = 0;
        while (ft_txe !== 1'b1 && timeout < 20000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (ft_txe !== 1'b1) begin
            $display("FAIL: TXE# never went high after 64-word burst (PHY DEPTH=64)");
            errors = errors + 1;
        end else
            $display("PHY TXE# went high after %0d clocks (TX FIFO full)", timeout);
        for (i = 0; i < 64; i = i + 1) begin
            host_pop_word(echo[i], echo_be[i]);
            if (echo[i] !== vec[i]) begin
                $display("MISMATCH backpressure word %0d: %h vs %h", i, echo[i], vec[i]);
                errors = errors + 1;
            end
        end
        $display("PASS TXE backpressure drain");

        if (timing_v != 0) begin
            $display("FAIL: %0d pad-timing violation(s)", timing_v);
            errors = errors + timing_v;
        end else
            $display("PASS timing: OE/RD/WR/BE/DATA checks clean");

        if (errors == 0) begin
            $display("PASS: 245 loopback PHY sim");
            $finish;
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $finish(1);
        end
    end

    initial begin
        #2_000_000;
        $display("FAIL: global timeout");
        $finish(1);
    end

endmodule
