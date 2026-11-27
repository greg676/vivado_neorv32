`timescale 1ns / 1ps
// PVLA capture datapath on the PR #18/#19 PHY.
//
// C_PHY=0 FT601  — ft601_sync_fifo ALWAYS_DRIVE, TX_BURST_WORDS=1024
//                  (Lucid DATA-before-WR, 4 KiB write bursts, NEVER RD)
// C_PHY=1 STREAM — 32-bit AXI-Stream master for a later SuperSpeed FIFO
//
// Counter / walking-one: one 32-bit word every clock while tx_ready, same
// pack as platforms/alchitry-au-v2/rtl/la (Au LA capture PASS).
// Live probes: 4 samples/word into a 1024-word ping-pong so the PHY never
// sees a short write (FT601 245 ping-pong commits USB IN on 4 KiB).
//
// Do not instantiate the old echo FWFT that starved WR mid-burst.
// Does not touch DDR3 / MIG / NeoRV32.
module pvla_capture #(
    parameter integer C_PHY             = 0,
    parameter integer C_HAS_AXI         = 1,
    parameter integer C_NUM_CH          = 8,
    parameter integer C_SAMPLE_MHZ      = 200,
    parameter integer C_PRETRIG_SAMPLES = 4096,
    parameter integer C_DEFAULT_POST    = 2048,
    parameter [1:0]   C_DEFAULT_SOURCE  = 2'd2
) (
    input  wire                  cap_clk,
    input  wire                  cap_rst,

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
    localparam [1:0]   SRC_LIVE = 2'd2;

    // CMD @ 0x00 — same 32-bit word as the host/AXI path.
    // [1:0] source  [2] arm  [3] soft_trig  [4] abort
    localparam integer CMD_ARM  = 2;
    localparam integer CMD_TRIG = 3;
    localparam integer CMD_ABRT = 4;

    (* keep = "true" *) wire unused_pre =
        (C_PRETRIG_SAMPLES[0] ^ C_DEFAULT_POST[0]);

    wire [7:0] probe_pad;
    generate
        if (C_NUM_CH >= 8)
            assign probe_pad = probe_i[7:0];
        else
            assign probe_pad = {{(8-C_NUM_CH){1'b0}}, probe_i};
    endgenerate

    // ── command / source ─────────────────────────────────────────
    reg [1:0]  source_r;
    reg        armed_r;
    reg        trig_r;
    reg        done_r;
    reg        ovf_r;
    reg [31:0] ovf_cnt_r;
    reg [31:0] drop_cnt_r;
    reg [7:0]  probe_d;
    wire       edge0 = probe_pad[0] & ~probe_d[0];

    wire auto_run = (C_HAS_AXI == 0);

    always @(posedge cap_clk) begin
        if (cap_rst) begin
            source_r  <= C_DEFAULT_SOURCE;
            armed_r   <= auto_run;
            trig_r    <= 1'b0;
            done_r    <= 1'b0;
            probe_d   <= 8'h00;
        end else begin
            probe_d <= probe_pad;
            if (cmd_valid) begin
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
            end else if (armed_r && !trig_r && (source_r == SRC_LIVE) && edge0) begin
                trig_r <= 1'b1;
            end else if (auto_run) begin
                armed_r <= 1'b1;
            end
        end
    end

    assign source_sel = source_r;
    assign armed      = armed_r;
    assign triggered  = trig_r || (source_r != SRC_LIVE && armed_r);
    assign cap_done   = done_r;

    wire is_pat = (source_r == SRC_CTR) || (source_r == SRC_WALK);

    // ── pattern: 4 samples / clock, advance on tx_ready (PR #19) ─
    wire        tx_ready;
    reg  [31:0] pat_n;
    wire [7:0]  pat_s0, pat_s1, pat_s2, pat_s3;
    wire        pat_en = armed_r && is_pat && tx_ready;

    function automatic [7:0] pat_samp;
        input [31:0] idx;
        begin
            if (source_r == SRC_WALK)
                pat_samp = 8'd1 << idx[2:0];
            else
                pat_samp = idx[7:0];
        end
    endfunction

    assign pat_s0 = pat_samp(pat_n);
    assign pat_s1 = pat_samp(pat_n + 32'd1);
    assign pat_s2 = pat_samp(pat_n + 32'd2);
    assign pat_s3 = pat_samp(pat_n + 32'd3);

    always @(posedge cap_clk) begin
        if (cap_rst || (cmd_valid && cmd_data[CMD_ARM]))
            pat_n <= 32'd0;
        else if (pat_en)
            pat_n <= pat_n + 32'd4;
    end

    wire [31:0] pat_word = {pat_s3, pat_s2, pat_s1, pat_s0};

    // ── live sampler ─────────────────────────────────────────────
    wire [7:0] live_a;
    wire [7:0] live_b;
    generate
        if (C_SAMPLE_MHZ == 200) begin : g_ddr
            genvar gi;
            for (gi = 0; gi < 8; gi = gi + 1) begin : g_iddr
                IDDR #(
                    .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),
                    .INIT_Q1     (1'b0),
                    .INIT_Q2     (1'b0),
                    .SRTYPE      ("ASYNC")
                ) u_iddr (
                    .Q1 (live_a[gi]),
                    .Q2 (live_b[gi]),
                    .C  (cap_clk),
                    .CE (1'b1),
                    .D  (probe_pad[gi]),
                    .R  (cap_rst),
                    .S  (1'b0)
                );
            end
        end else begin : g_sdr
            reg [7:0] live_r;
            always @(posedge cap_clk)
                live_r <= probe_pad;
            assign live_a = live_r;
            assign live_b = live_r;
        end
    endgenerate

    // Pack 4 unique samples per word. 100 MS/s: 4 clocks. 200 MS/s: 2 clocks.
    reg [1:0]  live_ph;
    reg [7:0]  live_h0, live_h1, live_h2;
    reg [31:0] live_word;
    reg        live_valid;

    always @(posedge cap_clk) begin
        if (cap_rst || !armed_r || is_pat) begin
            live_ph    <= 2'd0;
            live_valid <= 1'b0;
            live_word  <= 32'h0;
        end else if (C_SAMPLE_MHZ == 200) begin
            live_valid <= 1'b0;
            if (live_ph[0] == 1'b0) begin
                live_h0 <= live_a;
                live_h1 <= live_b;
                live_ph <= 2'd1;
            end else begin
                live_word  <= {live_b, live_a, live_h1, live_h0};
                live_valid <= 1'b1;
                live_ph    <= 2'd0;
            end
        end else begin
            live_valid <= 1'b0;
            case (live_ph)
                2'd0: begin live_h0 <= live_a; live_ph <= 2'd1; end
                2'd1: begin live_h1 <= live_a; live_ph <= 2'd2; end
                2'd2: begin live_h2 <= live_a; live_ph <= 2'd3; end
                default: begin
                    live_word  <= {live_a, live_h2, live_h1, live_h0};
                    live_valid <= 1'b1;
                    live_ph    <= 2'd0;
                end
            endcase
        end
    end

    // ── 4 KiB ping-pong (live only). Two 1024-word banks. ─────────
    (* ram_style = "block" *) reg [31:0] burst_mem [0:2047];
    reg        wr_bank, rd_bank;
    reg [9:0]  wr_n, rd_n;
    reg [1:0]  bank_full;
    reg        dumping;
    reg        dump_load;
    reg [31:0] rd_q;
    reg        live_ovf;

    wire [10:0] wr_addr = {wr_bank, wr_n};
    wire [10:0] rd_addr = {rd_bank, rd_n};
    wire        live_wr = live_valid && armed_r && !is_pat && !bank_full[wr_bank];

    always @(posedge cap_clk) begin
        if (live_wr)
            burst_mem[wr_addr] <= live_word;
        rd_q <= burst_mem[rd_addr];
    end

    always @(posedge cap_clk) begin
        if (cap_rst || (cmd_valid && (cmd_data[CMD_ABRT] || cmd_data[CMD_ARM]))) begin
            wr_bank   <= 1'b0;
            rd_bank   <= 1'b0;
            wr_n      <= 10'd0;
            rd_n      <= 10'd0;
            bank_full <= 2'b00;
            dumping   <= 1'b0;
            dump_load <= 1'b0;
            live_ovf  <= 1'b0;
        end else if (!is_pat) begin
            if (live_valid && armed_r) begin
                if (bank_full[wr_bank])
                    live_ovf <= 1'b1;
                else begin
                    if (wr_n == 10'd1023) begin
                        wr_n                <= 10'd0;
                        bank_full[wr_bank]  <= 1'b1;
                        wr_bank             <= ~wr_bank;
                    end else
                        wr_n <= wr_n + 1'b1;
                end
            end

            if (!dumping && !dump_load && bank_full[rd_bank]) begin
                dump_load <= 1'b1;
                rd_n      <= 10'd0;
            end else if (dump_load) begin
                dump_load <= 1'b0;
                dumping   <= 1'b1;
            end else if (dumping && tx_ready) begin
                if (rd_n == 10'd1023) begin
                    dumping            <= 1'b0;
                    bank_full[rd_bank] <= 1'b0;
                    rd_bank            <= ~rd_bank;
                    rd_n               <= 10'd0;
                end else
                    rd_n <= rd_n + 1'b1;
            end
        end
    end

    always @(posedge cap_clk) begin
        if (cap_rst) begin
            ovf_r     <= 1'b0;
            ovf_cnt_r <= 32'd0;
            drop_cnt_r<= 32'd0;
        end else begin
            if (live_ovf)
                ovf_r <= 1'b1;
            if (live_valid && armed_r && !is_pat && bank_full[wr_bank]) begin
                ovf_cnt_r  <= ovf_cnt_r + 1'b1;
                drop_cnt_r <= drop_cnt_r + 1'b1;
            end
        end
    end

    assign overflow_sticky = ovf_r;
    assign overflow_cnt    = ovf_cnt_r;
    assign drop_cnt        = drop_cnt_r;

    wire        live_tx_valid = dumping;
    wire [31:0] live_tx_data  = rd_q;

    wire        tx_valid = is_pat ? armed_r : live_tx_valid;
    wire [31:0] tx_data  = is_pat ? pat_word : live_tx_data;
    wire        tx_last  = (!is_pat) && dumping && (rd_n == 10'd1023);

    assign fifo_empty = is_pat ? 1'b0 : ~dumping;
    assign fifo_full  = |bank_full;

    // ── PHY / STREAM ─────────────────────────────────────────────
    wire [31:0] phy_rx_data;
    wire        phy_rx_valid;
    wire [3:0]  phy_rx_be;

    generate
        if (C_PHY == 0) begin : g_ft601
            ft601_sync_fifo #(
                .ALWAYS_DRIVE   (1),
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
            assign tx_active     = tx_ready;
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

    (* keep = "true" *) wire [31:0] rx_data_keep  = phy_rx_data;
    (* keep = "true" *) wire [3:0]  rx_be_keep    = phy_rx_be;
    (* keep = "true" *) wire        rx_valid_keep = phy_rx_valid;

endmodule
