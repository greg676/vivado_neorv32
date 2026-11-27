// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Pattern -> CDC -> AXI DDR model -> CDC -> ping-pong -> PHY WR bursts.
module tb_pvla_mig7_stream;
    localparam integer DEPTH = 2048;
    localparam [31:0]  BASE  = 32'h2000_0000;

    reg         ft_clk = 1'b0;
    reg         rst    = 1'b1;
    wire [31:0] ft_data;
    wire [3:0]  ft_be;
    wire        ft_oe, ft_rd, ft_wr;
    wire        overflow_sticky, fifo_empty, tx_active, calib_ok;
    wire [31:0] ddr_used;
    integer     wr_count = 0;
    integer     data_n   = 0;
    integer     errors   = 0;
    integer     i;
    integer     k;
    reg [31:0]  exp;

    assign ft_data = 32'bz;
    assign ft_be   = 4'bz;

    function automatic [31:0] pack4;
        input integer n;
        reg [7:0] a;
        begin
            a = n % 256;
            pack4 = {a + 8'd3, a + 8'd2, a + 8'd1, a};
        end
    endfunction

    wire [31:0]  awaddr, araddr;
    wire [7:0]   awlen, arlen;
    wire [2:0]   awsize, arsize;
    wire [1:0]   awburst, arburst;
    wire         awvalid, awready, arvalid, arready;
    wire [127:0] wdata, rdata;
    wire [15:0]  wstrb;
    wire         wlast, wvalid, wready, rlast, rvalid, rready;
    wire [1:0]   bresp, rresp;
    wire         bvalid, bready;

    pvla_mig7_capture_core #(
        .SOURCE      (2'd0),
        .DEPTH_WORDS (DEPTH),
        .BASE_ADDR   (BASE)
    ) u_core (
        .ft_clk          (ft_clk),
        .rst_ft          (rst),
        .axi_clk         (ft_clk),
        .axi_rst         (rst),
        .calib_done      (1'b1),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf          (1'b1),
        .ft_txe          (1'b0),
        .ft_oe           (ft_oe),
        .ft_rd           (ft_rd),
        .ft_wr           (ft_wr),
        .m_axi_awaddr    (awaddr),
        .m_axi_awlen     (awlen),
        .m_axi_awsize    (awsize),
        .m_axi_awburst   (awburst),
        .m_axi_awvalid   (awvalid),
        .m_axi_awready   (awready),
        .m_axi_wdata     (wdata),
        .m_axi_wstrb     (wstrb),
        .m_axi_wlast     (wlast),
        .m_axi_wvalid    (wvalid),
        .m_axi_wready    (wready),
        .m_axi_bresp     (bresp),
        .m_axi_bvalid    (bvalid),
        .m_axi_bready    (bready),
        .m_axi_araddr    (araddr),
        .m_axi_arlen     (arlen),
        .m_axi_arsize    (arsize),
        .m_axi_arburst   (arburst),
        .m_axi_arvalid   (arvalid),
        .m_axi_arready   (arready),
        .m_axi_rdata     (rdata),
        .m_axi_rresp     (rresp),
        .m_axi_rlast     (rlast),
        .m_axi_rvalid    (rvalid),
        .m_axi_rready    (rready),
        .overflow_sticky (overflow_sticky),
        .fifo_empty      (fifo_empty),
        .tx_active       (tx_active),
        .source_sel      (),
        .ddr_used_words  (ddr_used),
        .calib_ok        (calib_ok)
    );

    axi_sram_slave #(
        .DEPTH_WORDS (DEPTH),
        .BASE_ADDR   (BASE)
    ) u_mem (
        .clk           (ft_clk),
        .rst           (rst),
        .s_axi_awaddr  (awaddr),
        .s_axi_awlen   (awlen),
        .s_axi_awsize  (awsize),
        .s_axi_awburst (awburst),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),
        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (wstrb),
        .s_axi_wlast   (wlast),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),
        .s_axi_araddr  (araddr),
        .s_axi_arlen   (arlen),
        .s_axi_arsize  (arsize),
        .s_axi_arburst (arburst),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rlast   (rlast),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready)
    );

    always #5 ft_clk = ~ft_clk;

    always @(posedge ft_clk)
        if (!rst && ft_wr === 1'b0) begin
            wr_count = wr_count + 1;
            if (data_n < 256) begin
                k   = data_n * 4;
                exp = pack4(k);
                if (ft_data !== exp) begin
                    if (errors < 16)
                        $display("FAIL stream n=%0d got=0x%08x exp=0x%08x",
                                 data_n, ft_data, exp);
                    errors = errors + 1;
                end
                data_n = data_n + 1;
            end
        end

    initial begin
        repeat (8) @(posedge ft_clk);
        rst <= 1'b0;
        for (i = 0; i < 8000; i = i + 1)
            @(posedge ft_clk);
        $display("tb_pvla_mig7_stream wr_count=%0d data_n=%0d used=%0d ovf=%0d",
                 wr_count, data_n, ddr_used, overflow_sticky);
        if (wr_count < 1024)
            $display("FAIL tb_pvla_mig7_stream expected a 4 KiB WR burst");
        else if (errors != 0)
            $display("FAIL tb_pvla_mig7_stream packed-counter errors=%0d", errors);
        else
            $display("PASS tb_pvla_mig7_stream");
        $finish;
    end
endmodule
