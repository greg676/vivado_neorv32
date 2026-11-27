`timescale 1ns / 1ps
// PVLA capture: visible 4/8/16 packer -> 4 KiB ping-pong -> Lucid WR PHY.
//
// C_PHY=0 FT601  — ft601_sync_fifo, TX_BURST_WORDS=1024, rx_ready=0
//                  C_PAD_MODE 0 = IOBUF 245 (default)  1 = ALWAYS_DRIVE
// C_PHY=1 STREAM — 32-bit AXI-Stream master
//
// One sample per samp_clk/C_SAMPLE_DIV. N samples fill one 32-bit USB word.
// Packed words land in two 1024-word BRAM banks so ST_WRITE never sees a
// short burst (FT601 245 ping-pong commits USB IN on 4 KiB).
//
// Does not touch DDR3 / MIG / NeoRV32.
module pvla_capture #(
    parameter integer C_PHY             = 0,
    parameter integer C_HAS_AXI         = 0,
    parameter integer C_NUM_CH          = 8,
    parameter integer C_SAMPLE_MHZ      = 100,
    parameter integer C_SAMPLE_DIV      = 1,
    parameter integer C_SAMPLE_CLK_SRC  = 0,
    parameter integer C_INPUT_PATH      = 0,
    parameter integer C_PAD_MODE        = 0,
    parameter integer C_PRETRIG_SAMPLES = 4096,
    parameter integer C_DEFAULT_POST    = 2048,
    parameter [1:0]   C_DEFAULT_SOURCE  = 2'd0
) (
    input  wire                  cap_clk,
    input  wire                  cap_rst,
    input  wire                  samp_clk,
    input  wire                  samp_rst,

    input  wire [C_NUM_CH-1:0]   probe_i,

    input  wire                  cmd_valid,
    input  wire [31:0]           cmd_data,

    inout  wire [31:0]           ft_data,
    inout  wire [3:0]            ft_be,
    input  wire                  ft_rxf,
    input  wire                  ft_txe,
    output wire                  ft_oe,
    output wire                  ft_rd,
    output wire                  ft_wr,

    output wire [31:0]           m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    output wire                  overflow_sticky,
    output wire                  fifo_empty,
    output wire                  fifo_full,
    output wire                  tx_active,
    output wire [1:0]            source_sel,
    output wire                  armed,
    output wire                  triggered,
    output wire                  cap_done,
    output wire [31:0]           overflow_cnt,
    output wire [31:0]           drop_cnt
);

    localparam integer BURST    = 1024;
    localparam [1:0]   SRC_CTR  = 2'd0;
    localparam [1:0]   SRC_WALK = 2'd1;
    localparam [1:0]   SRC_PROBE= 2'd2;
    localparam integer CMD_ARM  = 2;
    localparam integer CMD_TRIG = 3;
    localparam integer CMD_ABRT = 4;
    localparam integer DIV      = (C_SAMPLE_DIV < 1) ? 1 : C_SAMPLE_DIV;

    (* keep = "true" *) wire unused_cfg =
        (C_SAMPLE_MHZ != 0) ^ (C_PRETRIG_SAMPLES != 0) ^ (C_DEFAULT_POST != 0)
        ^ (C_SAMPLE_CLK_SRC != 0) ^ (C_PAD_MODE != 0);

    // ── command / source (sample domain) ─────────────────────────
    // C_INPUT_PATH=1 (external) forces probe pins; never mix with pattern.
    reg [1:0]  source_r;
    reg        armed_r;
    reg        trig_r;
    reg        done_r;
    reg [C_NUM_CH-1:0] probe_d;
    wire       edge0 = probe_i[0] & ~probe_d[0];
    wire       auto_run = (C_HAS_AXI == 0);
    wire [1:0] src_eff = (C_INPUT_PATH != 0) ? SRC_PROBE : source_r;

    always @(posedge samp_clk) begin
        if (samp_rst) begin
            source_r <= C_DEFAULT_SOURCE;
            armed_r  <= auto_run;
            trig_r   <= 1'b0;
            done_r   <= 1'b0;
            probe_d  <= {C_NUM_CH{1'b0}};
        end else begin
            probe_d <= probe_i;
            if (cmd_valid) begin
                if (C_INPUT_PATH == 0)
                    source_r <= cmd_data[1:0];
                if (cmd_data[CMD_ABRT]) begin
                    armed_r <= 1'b0;
                    trig_r  <= 1'b0;
                    done_r  <= 1'b1;
                end else if (cmd_data[CMD_ARM]) begin
                    armed_r <= 1'b1;
                    trig_r  <= 1'b0;
                    done_r  <= 1'b0;
                end
                if (cmd_data[CMD_TRIG])
                    trig_r <= 1'b1;
            end else if (armed_r && !trig_r && (src_eff == SRC_PROBE) && edge0) begin
                trig_r <= 1'b1;
            end else if (auto_run) begin
                armed_r <= 1'b1;
            end
        end
    end

    assign source_sel = src_eff;
    assign armed      = armed_r;
    assign triggered  = trig_r || (src_eff != SRC_PROBE && armed_r);
    assign cap_done   = done_r;

    // ── sample strobe: samp_clk / C_SAMPLE_DIV ───────────────────
    reg [3:0] div_cnt;
    wire      div_tick = (DIV == 1) || (div_cnt == DIV[3:0] - 4'd1);

    always @(posedge samp_clk) begin
        if (samp_rst || !armed_r)
            div_cnt <= 4'd0;
        else if (div_tick)
            div_cnt <= 4'd0;
        else
            div_cnt <= div_cnt + 4'd1;
    end

    wire [C_NUM_CH-1:0] int_sample;
    wire                int_valid;
    wire                ext_ce = armed_r && div_tick;

    pvla_internal_src #(
        .C_NUM_CH (C_NUM_CH)
    ) u_src (
        .clk          (samp_clk),
        .rst          (samp_rst || !armed_r),
        .ce           (ext_ce && (C_INPUT_PATH == 0) && (src_eff != SRC_PROBE)),
        .src          (src_eff),
        .probe_i      (probe_i),
        .sample_o     (int_sample),
        .sample_valid (int_valid)
    );

    // External / BD probe: register on the divider tick (LVCMOS33 pins or canvas).
    reg [C_NUM_CH-1:0] probe_r;
    reg                probe_v;
    always @(posedge samp_clk) begin
        if (samp_rst || !armed_r) begin
            probe_r <= {C_NUM_CH{1'b0}};
            probe_v <= 1'b0;
        end else begin
            probe_v <= 1'b0;
            if (ext_ce && ((C_INPUT_PATH != 0) || (src_eff == SRC_PROBE))) begin
                probe_r <= probe_i;
                probe_v <= 1'b1;
            end
        end
    end

    wire [C_NUM_CH-1:0] sample_w = (int_valid) ? int_sample : probe_r;
    wire                sample_v = int_valid | probe_v;

    // ── packer (sample domain) ───────────────────────────────────
    wire [31:0] packed_word;
    wire        packed_valid;
    wire        packed_ready;
    wire        pack_ready;

    pvla_word_packer #(
        .C_NUM_CH (C_NUM_CH)
    ) u_pack (
        .clk          (samp_clk),
        .rst          (samp_rst),
        .arm          (armed_r),
        .sample_i     (sample_w),
        .sample_valid (sample_v),
        .sample_ready (pack_ready),
        .word_o       (packed_word),
        .word_valid   (packed_valid),
        .word_ready   (packed_ready)
    );

    // ── 4 KiB ping-pong: write samp_clk, dump cap_clk ────────────
    (* ram_style = "block" *) reg [31:0] burst_mem [0:2047];

    reg        wr_bank;
    reg [9:0]  wr_n;
    reg [1:0]  wr_fill_tog;
    reg        rd_bank;
    reg [9:0]  rd_n;
    reg [1:0]  rd_empty_tog;
    reg        dumping;
    reg        dump_load;
    reg [31:0] rd_q;
    (* ASYNC_REG = "TRUE" *) reg [1:0] rd_empty_s1, rd_empty_s2;
    (* ASYNC_REG = "TRUE" *) reg [1:0] wr_fill_c1, wr_fill_c2;
    wire [1:0] rd_empty_w = rd_empty_s2;
    wire       wr_full    = (wr_fill_tog[wr_bank] != rd_empty_w[wr_bank]);

    assign packed_ready = !wr_full;

    always @(posedge samp_clk) begin
        if (samp_rst) begin
            rd_empty_s1 <= 2'b00;
            rd_empty_s2 <= 2'b00;
        end else begin
            rd_empty_s1 <= rd_empty_tog;
            rd_empty_s2 <= rd_empty_s1;
        end
    end

    always @(posedge samp_clk) begin
        if (samp_rst || (cmd_valid && (cmd_data[CMD_ABRT] || cmd_data[CMD_ARM]))) begin
            wr_bank      <= 1'b0;
            wr_n         <= 10'd0;
            wr_fill_tog  <= 2'b00;
        end else if (packed_valid && packed_ready) begin
            burst_mem[{wr_bank, wr_n}] <= packed_word;
            if (wr_n == 10'd1023) begin
                wr_n                  <= 10'd0;
                wr_fill_tog[wr_bank]  <= ~wr_fill_tog[wr_bank];
                wr_bank               <= ~wr_bank;
            end else
                wr_n <= wr_n + 10'd1;
        end
    end

    wire       rd_full = (wr_fill_c2[rd_bank] != rd_empty_tog[rd_bank]);
    wire       tx_ready;

    always @(posedge cap_clk) begin
        if (cap_rst) begin
            wr_fill_c1 <= 2'b00;
            wr_fill_c2 <= 2'b00;
            rd_q       <= 32'h0;
        end else begin
            wr_fill_c1 <= wr_fill_tog;
            wr_fill_c2 <= wr_fill_c1;
            rd_q       <= burst_mem[{rd_bank, rd_n}];
        end
    end

    always @(posedge cap_clk) begin
        if (cap_rst) begin
            rd_bank       <= 1'b0;
            rd_n          <= 10'd0;
            rd_empty_tog  <= 2'b00;
            dumping       <= 1'b0;
            dump_load     <= 1'b0;
        end else if (!dumping && !dump_load && rd_full) begin
            dump_load <= 1'b1;
            rd_n      <= 10'd0;
        end else if (dump_load) begin
            dump_load <= 1'b0;
            dumping   <= 1'b1;
        end else if (dumping && tx_ready) begin
            if (rd_n == 10'd1023) begin
                dumping                 <= 1'b0;
                rd_empty_tog[rd_bank]   <= ~rd_empty_tog[rd_bank];
                rd_bank                 <= ~rd_bank;
                rd_n                    <= 10'd0;
            end else
                rd_n <= rd_n + 10'd1;
        end
    end

    // Overflow: a packed word arrived while the write bank was full.
    reg        ovf_r;
    reg [31:0] ovf_cnt_r;
    reg [31:0] drop_cnt_r;
    always @(posedge samp_clk) begin
        if (samp_rst) begin
            ovf_r      <= 1'b0;
            ovf_cnt_r  <= 32'd0;
            drop_cnt_r <= 32'd0;
        end else if (packed_valid && !packed_ready) begin
            ovf_r      <= 1'b1;
            ovf_cnt_r  <= ovf_cnt_r + 32'd1;
            drop_cnt_r <= drop_cnt_r + 32'd1;
        end else if (sample_v && !pack_ready) begin
            ovf_r      <= 1'b1;
            ovf_cnt_r  <= ovf_cnt_r + 32'd1;
            drop_cnt_r <= drop_cnt_r + 32'd1;
        end
    end

    assign overflow_sticky = ovf_r;
    assign overflow_cnt    = ovf_cnt_r;
    assign drop_cnt        = drop_cnt_r;
    assign fifo_empty      = ~dumping;
    assign fifo_full       = wr_full;

    wire        tx_valid = dumping;
    wire [31:0] tx_data  = rd_q;
    wire        tx_last  = dumping && (rd_n == 10'd1023);

    // ── PHY / STREAM ─────────────────────────────────────────────
    wire [31:0] phy_rx_data;
    wire        phy_rx_valid;
    wire [3:0]  phy_rx_be;

    generate
        if (C_PHY == 0) begin : g_ft601
            ft601_sync_fifo #(
                .ALWAYS_DRIVE   (C_PAD_MODE),
                .TX_BURST_WORDS (BURST)
            ) u_phy (
                .ft_clk   (cap_clk),
                .rst      (cap_rst),
                .ft_data  (ft_data),
                .ft_be    (ft_be),
                .ft_rxf   (ft_rxf),
                .ft_txe   (ft_txe),
                .ft_oe    (ft_oe),
                .ft_rd    (ft_rd),
                .ft_wr    (ft_wr),
                .rx_data  (phy_rx_data),
                .rx_be    (phy_rx_be),
                .rx_valid (phy_rx_valid),
                .rx_ready (1'b0),
                .tx_data  (tx_data),
                .tx_be    (4'hF),
                .tx_valid (tx_valid),
                .tx_ready (tx_ready)
            );

            assign m_axis_tdata  = 32'h0;
            assign m_axis_tvalid = 1'b0;
            assign m_axis_tlast  = 1'b0;
            assign tx_active     = dumping;
        end else begin : g_stream
            assign phy_rx_data  = 32'h0;
            assign phy_rx_be    = 4'h0;
            assign phy_rx_valid = 1'b0;

            assign ft_data = 32'bz;
            assign ft_be   = 4'bz;
            assign ft_oe   = 1'b1;
            assign ft_rd   = 1'b1;
            assign ft_wr   = 1'b1;

            assign tx_ready      = m_axis_tready;
            assign m_axis_tdata  = tx_data;
            assign m_axis_tvalid = tx_valid;
            assign m_axis_tlast  = tx_last;
            assign tx_active     = tx_valid && tx_ready;
        end
    endgenerate

    (* keep = "true" *) wire [31:0] packed_keep    = packed_word;
    (* keep = "true" *) wire [31:0] rx_data_keep   = phy_rx_data;
    (* keep = "true" *) wire [3:0]  rx_be_keep     = phy_rx_be;
    (* keep = "true" *) wire        rx_valid_keep  = phy_rx_valid;

endmodule
