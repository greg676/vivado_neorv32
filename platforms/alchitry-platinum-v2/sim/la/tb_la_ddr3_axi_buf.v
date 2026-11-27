`timescale 1ns / 1ps
// Packed counter through the AXI DDR buffer + behavioral MIG stand-in.
module tb_la_ddr3_axi_buf;
    localparam integer DEPTH = 2048;
    localparam integer N     = 256;
    localparam [31:0]  BASE  = 32'h2000_0000;

    reg         clk = 1'b0;
    reg         rst = 1'b1;
    wire [31:0] s_tdata;
    wire        s_tready;
    wire [31:0] m_tdata;
    wire        m_tvalid;
    reg         m_tready = 1'b0;

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
    wire [31:0]  used;
    wire         ovf;

    wire [7:0] s0, s1, s2, s3;
    assign s_tdata = {s3, s2, s1, s0};

    integer errors = 0;
    integer got_n  = 0;
    integer k;
    reg [31:0] exp;

    function automatic [31:0] pack4;
        input integer n;
        reg [7:0] a;
        begin
            a = n % 256;
            pack4 = {a + 8'd3, a + 8'd2, a + 8'd1, a};
        end
    endfunction

    la_pattern u_pat (
        .clk    (clk),
        .rst    (rst),
        .enable (s_tready),
        .s0     (s0),
        .s1     (s1),
        .s2     (s2),
        .s3     (s3)
    );

    la_ddr3_axi_buf #(
        .DEPTH_WORDS (DEPTH),
        .BASE_ADDR   (BASE)
    ) u_buf (
        .axi_clk         (clk),
        .axi_rst         (rst),
        .calib_done      (1'b1),
        .s_tdata         (s_tdata),
        .s_tvalid        (1'b1),
        .s_tready        (s_tready),
        .m_tdata         (m_tdata),
        .m_tvalid        (m_tvalid),
        .m_tready        (m_tready),
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
        .used_words      (used),
        .overflow_sticky (ovf)
    );

    axi_sram_slave #(
        .DEPTH_WORDS (DEPTH),
        .BASE_ADDR   (BASE)
    ) u_mem (
        .clk           (clk),
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

    always #5 clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        repeat (8) @(posedge clk);
        m_tready <= 1'b1;
        while (got_n < N) begin
            @(posedge clk);
            if (m_tvalid && m_tready) begin
                k   = got_n * 4;
                exp = pack4(k);
                if (m_tdata !== exp) begin
                    if (errors < 16)
                        $display("FAIL n=%0d got=0x%08x exp=0x%08x",
                                 got_n, m_tdata, exp);
                    errors = errors + 1;
                end
                got_n = got_n + 1;
            end
        end
        if (errors == 0)
            $display("PASS tb_la_ddr3_axi_buf got=%0d used=%0d", got_n, used);
        else
            $display("FAIL tb_la_ddr3_axi_buf errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL tb_la_ddr3_axi_buf timeout got=%0d", got_n);
        $finish;
    end
endmodule
