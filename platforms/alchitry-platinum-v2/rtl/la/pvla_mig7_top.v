`timescale 1ns / 1ps
// Separate Pt V2 top: PVLA capture + MIG7 256 MB DDR3 buffer + 4 KiB FT601 PHY.
//
// Au has no DDR — do not build this for xc7a35t. PHY is the proven Lucid
// WR / ALWAYS_DRIVE 1024-word burst core. Dual 4 KiB BRAMs still sit in
// front of the PHY. DDR3 is the large capture store, not a PHY replacement.
//
// No NeoRV32 (fabric AXI master talks to MIG). No QSPI. RAM program only.
//
// C_SIM_MEM=1: behavioral AXI SRAM (Icarus). 0: pvla_mig7_bd_wrapper (Vivado).
module pvla_mig7_top #(
    parameter [1:0]   SOURCE      = 2'd0,
    parameter integer C_SIM_MEM   = 0,
    parameter integer DEPTH_WORDS = 67108864,
    parameter [31:0]  BASE_ADDR   = 32'h2000_0000
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [7:0]  led,

    input  wire        ft_clk,
    inout  wire [31:0] ft_data,
    inout  wire [3:0]  ft_be,
    input  wire        ft_rxf,
    input  wire        ft_txe,
    output wire        ft_oe,
    output wire        ft_rd,
    output wire        ft_wr,
    output wire        ft_reset,
    output wire        ft_wakeup,

    output wire [13:0] DDR3_0_addr,
    output wire [2:0]  DDR3_0_ba,
    output wire        DDR3_0_cas_n,
    output wire [0:0]  DDR3_0_ck_n,
    output wire [0:0]  DDR3_0_ck_p,
    output wire [0:0]  DDR3_0_cke,
    output wire [0:0]  DDR3_0_cs_n,
    output wire [1:0]  DDR3_0_dm,
    inout  wire [15:0] DDR3_0_dq,
    inout  wire [1:0]  DDR3_0_dqs_n,
    inout  wire [1:0]  DDR3_0_dqs_p,
    output wire [0:0]  DDR3_0_odt,
    output wire        DDR3_0_ras_n,
    output wire        DDR3_0_reset_n,
    output wire        DDR3_0_we_n
);

    wire rst_ft;
    wire axi_clk;
    wire axi_rst;
    wire calib_done;

    wire [31:0]  awaddr;
    wire [7:0]   awlen;
    wire [2:0]   awsize;
    wire [1:0]   awburst;
    wire         awvalid, awready;
    wire [127:0] wdata;
    wire [15:0]  wstrb;
    wire         wlast, wvalid, wready;
    wire [1:0]   bresp;
    wire         bvalid, bready;
    wire [31:0]  araddr;
    wire [7:0]   arlen;
    wire [2:0]   arsize;
    wire [1:0]   arburst;
    wire         arvalid, arready;
    wire [127:0] rdata;
    wire [1:0]   rresp;
    wire         rlast, rvalid, rready;

    wire        overflow_sticky;
    wire        fifo_empty;
    wire        tx_active;
    wire [1:0]  source_sel;
    wire [31:0] ddr_used;
    wire        calib_ok;

    ft601_reset u_reset (
        .clk_board   (clk),
        .rst_n_async (rst_n),
        .ft_clk      (ft_clk),
        .ft_reset    (ft_reset),
        .rst_ft      (rst_ft)
    );

    assign ft_wakeup = 1'b1;

    generate
        if (C_SIM_MEM != 0) begin : g_sim
            assign axi_clk    = ft_clk;
            assign axi_rst    = rst_ft;
            assign calib_done = 1'b1;
            assign DDR3_0_addr    = 14'd0;
            assign DDR3_0_ba      = 3'd0;
            assign DDR3_0_cas_n   = 1'b1;
            assign DDR3_0_ck_n    = 1'b1;
            assign DDR3_0_ck_p    = 1'b0;
            assign DDR3_0_cke     = 1'b0;
            assign DDR3_0_cs_n    = 1'b1;
            assign DDR3_0_dm      = 2'b00;
            assign DDR3_0_odt     = 1'b0;
            assign DDR3_0_ras_n   = 1'b1;
            assign DDR3_0_reset_n = 1'b0;
            assign DDR3_0_we_n    = 1'b1;

            axi_sram_slave #(
                .DEPTH_WORDS (DEPTH_WORDS),
                .BASE_ADDR   (BASE_ADDR)
            ) u_mem (
                .clk           (axi_clk),
                .rst           (axi_rst),
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
        end else begin : g_mig
            pvla_mig7_bd_wrapper u_bd (
                .clk                 (clk),
                .resetn              (rst_n),
                .DDR3_0_addr         (DDR3_0_addr),
                .DDR3_0_ba           (DDR3_0_ba),
                .DDR3_0_cas_n        (DDR3_0_cas_n),
                .DDR3_0_ck_n         (DDR3_0_ck_n),
                .DDR3_0_ck_p         (DDR3_0_ck_p),
                .DDR3_0_cke          (DDR3_0_cke),
                .DDR3_0_cs_n         (DDR3_0_cs_n),
                .DDR3_0_dm           (DDR3_0_dm),
                .DDR3_0_dq           (DDR3_0_dq),
                .DDR3_0_dqs_n        (DDR3_0_dqs_n),
                .DDR3_0_dqs_p        (DDR3_0_dqs_p),
                .DDR3_0_odt          (DDR3_0_odt),
                .DDR3_0_ras_n        (DDR3_0_ras_n),
                .DDR3_0_reset_n      (DDR3_0_reset_n),
                .DDR3_0_we_n         (DDR3_0_we_n),
                .ui_clk              (axi_clk),
                .ui_clk_sync_rst     (axi_rst),
                .init_calib_complete (calib_done),
                .S00_AXI_awaddr      (awaddr),
                .S00_AXI_awlen       (awlen),
                .S00_AXI_awsize      (awsize),
                .S00_AXI_awburst     (awburst),
                .S00_AXI_awlock      (1'b0),
                .S00_AXI_awcache     (4'b0011),
                .S00_AXI_awprot      (3'b000),
                .S00_AXI_awqos       (4'b0000),
                .S00_AXI_awvalid     (awvalid),
                .S00_AXI_awready     (awready),
                .S00_AXI_wdata       (wdata),
                .S00_AXI_wstrb       (wstrb),
                .S00_AXI_wlast       (wlast),
                .S00_AXI_wvalid      (wvalid),
                .S00_AXI_wready      (wready),
                .S00_AXI_bresp       (bresp),
                .S00_AXI_bvalid      (bvalid),
                .S00_AXI_bready      (bready),
                .S00_AXI_araddr      (araddr),
                .S00_AXI_arlen       (arlen),
                .S00_AXI_arsize      (arsize),
                .S00_AXI_arburst     (arburst),
                .S00_AXI_arlock      (1'b0),
                .S00_AXI_arcache     (4'b0011),
                .S00_AXI_arprot      (3'b000),
                .S00_AXI_arqos       (4'b0000),
                .S00_AXI_arvalid     (arvalid),
                .S00_AXI_arready     (arready),
                .S00_AXI_rdata       (rdata),
                .S00_AXI_rresp       (rresp),
                .S00_AXI_rlast       (rlast),
                .S00_AXI_rvalid      (rvalid),
                .S00_AXI_rready      (rready)
            );
        end
    endgenerate

    pvla_mig7_capture_core #(
        .SOURCE      (SOURCE),
        .DEPTH_WORDS (DEPTH_WORDS),
        .BASE_ADDR   (BASE_ADDR)
    ) u_core (
        .ft_clk          (ft_clk),
        .rst_ft          (rst_ft),
        .axi_clk         (axi_clk),
        .axi_rst         (axi_rst),
        .calib_done      (calib_done),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf          (ft_rxf),
        .ft_txe          (ft_txe),
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
        .source_sel      (source_sel),
        .ddr_used_words  (ddr_used),
        .calib_ok        (calib_ok)
    );

    reg [24:0] blink_board;
    reg [24:0] blink_ft;
    always @(posedge clk)
        blink_board <= blink_board + 1'b1;
    always @(posedge ft_clk)
        blink_ft <= blink_ft + 1'b1;

    assign led[0] = blink_board[24];
    assign led[1] = blink_ft[24];
    assign led[2] = calib_ok;
    assign led[3] = tx_active;
    assign led[4] = fifo_empty;
    assign led[5] = overflow_sticky;
    assign led[6] = ddr_used[16];
    assign led[7] = source_sel[0];

endmodule
