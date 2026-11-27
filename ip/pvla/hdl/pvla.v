`timescale 1ns / 1ps
// PVLA — PulseView logic analyzer, packaged as a Vivado catalog IP.
//
// Educational 4/8/16-channel packer: N samples fill one 32-bit USB word.
// Au V2 + Ft+ FT601 first. SRAM/BRAM only. No DDR3, no QSPI, no NeoRV32.
//
// C_PHY        0 = FT601 (default)   1 = STREAM (m_axis_* for another PHY)
// C_BOARD      0 = PT_ALPHA  1 = PT_V2  2 = AU_V2 (default)
// C_INPUT_PATH 0 = internal fabric    1 = external LVCMOS33 pins
// C_PAD_MODE   0 = IOBUF 245          1 = ALWAYS_DRIVE (proven TX OBUF)
//
// Probe ports stay user-wired. Optional Br Bank A XDC is off by default.
module pvla #(
    parameter integer C_NUM_CH          = 8,
    parameter integer C_SAMPLE_MHZ      = 100,
    parameter integer C_SAMPLE_DIV      = 1,
    parameter integer C_SAMPLE_CLK_SRC  = 0,
    parameter integer C_INPUT_PATH      = 0,
    parameter integer C_PAD_MODE        = 0,
    parameter integer C_PRETRIG_SAMPLES = 4096,
    parameter integer C_DEFAULT_POST    = 2048,
    parameter integer C_PHY             = 0,
    parameter integer C_BOARD           = 2,
    parameter integer C_HAS_AXI         = 0,
    parameter integer C_INCLUDE_BR_XDC  = 0,
    parameter integer C_DEFAULT_SOURCE  = 0,
    parameter integer C_S_AXI_ADDR_WIDTH = 8,
    parameter integer C_S_AXI_DATA_WIDTH = 32
) (
    input  wire                        clk,
    input  wire                        rst_n,

    input  wire                        sample_clk,
    input  wire                        sample_rst_n,

    input  wire [C_NUM_CH-1:0]         probe_i,

    output wire [7:0]                  status_o,

    input  wire                        ft_clk,
    inout  wire [31:0]                 ft_data,
    inout  wire [3:0]                  ft_be,
    input  wire                        ft_rxf,
    input  wire                        ft_txe,
    output wire                        ft_oe,
    output wire                        ft_rd,
    output wire                        ft_wr,
    output wire                        ft_reset,
    output wire                        ft_wakeup,

    output wire [31:0]                 m_axis_tdata,
    output wire                        m_axis_tvalid,
    input  wire                        m_axis_tready,
    output wire                        m_axis_tlast,
    output wire [3:0]                  m_axis_tkeep,

    input  wire                        s_axi_aclk,
    input  wire                        s_axi_aresetn,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]                  s_axi_awprot,
    input  wire                        s_axi_awvalid,
    output wire                        s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                        s_axi_wvalid,
    output wire                        s_axi_wready,
    output wire [1:0]                  s_axi_bresp,
    output wire                        s_axi_bvalid,
    input  wire                        s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]                  s_axi_arprot,
    input  wire                        s_axi_arvalid,
    output wire                        s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                  s_axi_rresp,
    output wire                        s_axi_rvalid,
    input  wire                        s_axi_rready
);

    // C_BOARD / C_INCLUDE_BR_XDC select which IP XDC is packaged.
    (* keep = "true" *) wire unused_cfg = (C_BOARD != 0) ^ (C_INCLUDE_BR_XDC != 0);

    wire phy_clk = (C_PHY == 0) ? ft_clk : sample_clk;
    wire samp_clk = (C_SAMPLE_CLK_SRC != 0) ? sample_clk : phy_clk;
    wire cap_rst;
    wire samp_rst;
    wire rst_ft;
    wire ft_reset_w;

    generate
        if (C_PHY == 0) begin : g_ft_reset
            ft601_reset #(
                .HOLD_CYCLES(100000)
            ) u_reset (
                .clk_board   (clk),
                .rst_n_async (rst_n),
                .ft_clk      (ft_clk),
                .ft_reset    (ft_reset_w),
                .rst_ft      (rst_ft)
            );
            assign cap_rst   = rst_ft;
            assign ft_reset  = ft_reset_w;
            assign ft_wakeup = 1'b1;
        end else begin : g_stream_reset
            assign cap_rst   = ~sample_rst_n;
            assign rst_ft    = 1'b0;
            assign ft_reset  = 1'b1;
            assign ft_wakeup = 1'b1;
        end
    endgenerate

    assign samp_rst = (C_SAMPLE_CLK_SRC != 0) ? ~sample_rst_n : cap_rst;

    wire        cmd_valid;
    wire [31:0] cmd_data;
    wire        overflow_sticky;
    wire        fifo_empty;
    wire        fifo_full;
    wire        tx_active;
    wire [1:0]  source_sel;
    wire        armed;
    wire        triggered;
    wire        cap_done;
    wire [31:0] overflow_cnt;
    wire [31:0] drop_cnt;

    generate
        if (C_HAS_AXI != 0) begin : g_axi
            pvla_axi_lite u_axi (
                .s_axi_aclk    (s_axi_aclk),
                .s_axi_aresetn (s_axi_aresetn),
                .s_axi_awaddr  (s_axi_awaddr),
                .s_axi_awprot  (s_axi_awprot),
                .s_axi_awvalid (s_axi_awvalid),
                .s_axi_awready (s_axi_awready),
                .s_axi_wdata   (s_axi_wdata),
                .s_axi_wstrb   (s_axi_wstrb),
                .s_axi_wvalid  (s_axi_wvalid),
                .s_axi_wready  (s_axi_wready),
                .s_axi_bresp   (s_axi_bresp),
                .s_axi_bvalid  (s_axi_bvalid),
                .s_axi_bready  (s_axi_bready),
                .s_axi_araddr  (s_axi_araddr),
                .s_axi_arprot  (s_axi_arprot),
                .s_axi_arvalid (s_axi_arvalid),
                .s_axi_arready (s_axi_arready),
                .s_axi_rdata   (s_axi_rdata),
                .s_axi_rresp   (s_axi_rresp),
                .s_axi_rvalid  (s_axi_rvalid),
                .s_axi_rready  (s_axi_rready),
                .cap_clk       (samp_clk),
                .cap_rst       (samp_rst),
                .cmd_valid     (cmd_valid),
                .cmd_data      (cmd_data),
                .armed         (armed),
                .triggered     (triggered),
                .cap_done      (cap_done),
                .overflow_sticky (overflow_sticky),
                .source_sel    (source_sel),
                .overflow_cnt  (overflow_cnt),
                .drop_cnt      (drop_cnt)
            );
        end else begin : g_no_axi
            assign cmd_valid     = 1'b0;
            assign cmd_data      = 32'h0;
            assign s_axi_awready = 1'b0;
            assign s_axi_wready  = 1'b0;
            assign s_axi_bresp   = 2'b00;
            assign s_axi_bvalid  = 1'b0;
            assign s_axi_arready = 1'b0;
            assign s_axi_rdata   = 32'h0;
            assign s_axi_rresp   = 2'b00;
            assign s_axi_rvalid  = 1'b0;
        end
    endgenerate

    pvla_capture #(
        .C_PHY             (C_PHY),
        .C_HAS_AXI         (C_HAS_AXI),
        .C_NUM_CH          (C_NUM_CH),
        .C_SAMPLE_MHZ      (C_SAMPLE_MHZ),
        .C_SAMPLE_DIV      (C_SAMPLE_DIV),
        .C_SAMPLE_CLK_SRC  (C_SAMPLE_CLK_SRC),
        .C_INPUT_PATH      (C_INPUT_PATH),
        .C_PAD_MODE        (C_PAD_MODE),
        .C_PRETRIG_SAMPLES (C_PRETRIG_SAMPLES),
        .C_DEFAULT_POST    (C_DEFAULT_POST),
        .C_DEFAULT_SOURCE  (C_DEFAULT_SOURCE[1:0])
    ) u_cap (
        .cap_clk         (phy_clk),
        .cap_rst         (cap_rst),
        .samp_clk        (samp_clk),
        .samp_rst        (samp_rst),
        .probe_i         (probe_i),
        .cmd_valid       (cmd_valid),
        .cmd_data        (cmd_data),
        .ft_data         (ft_data),
        .ft_be           (ft_be),
        .ft_rxf          (ft_rxf),
        .ft_txe          (ft_txe),
        .ft_oe           (ft_oe),
        .ft_rd           (ft_rd),
        .ft_wr           (ft_wr),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast),
        .overflow_sticky (overflow_sticky),
        .fifo_empty      (fifo_empty),
        .fifo_full       (fifo_full),
        .tx_active       (tx_active),
        .source_sel      (source_sel),
        .armed           (armed),
        .triggered       (triggered),
        .cap_done        (cap_done),
        .overflow_cnt    (overflow_cnt),
        .drop_cnt        (drop_cnt)
    );

    assign m_axis_tkeep = 4'hF;

    assign status_o[0] = armed;
    assign status_o[1] = triggered;
    assign status_o[2] = cap_done;
    assign status_o[3] = overflow_sticky;
    assign status_o[4] = fifo_full;
    assign status_o[5] = (source_sel == 2'd2);
    assign status_o[6] = tx_active;
    assign status_o[7] = fifo_empty;

endmodule
