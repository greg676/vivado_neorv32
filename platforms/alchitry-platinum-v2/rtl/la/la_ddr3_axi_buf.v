// SPDX-FileCopyrightText: 2026 Greg Jackson
// SPDX-License-Identifier: MIT
`timescale 1ns / 1ps
// Fabric AXI4 master: 32-bit sample stream <-> 128-bit MIG7 window.
//
// Pt DDR3 is 256 MB at 0x2000_0000 (same map as neorv_basic_plus).
// Packs four 32-bit words per AXI beat. One write burst and one read
// burst of 16 beats (64 words / 256 B) may be outstanding together so
// 400 MB/s fill and dump both fit on 128-bit @ 100 MHz ui_clk.
//
// Does not instantiate NeoRV32. Sampler back-pressure is s_tready
// (DDR occupancy), not PHY TXE.
module la_ddr3_axi_buf #(
    parameter integer DEPTH_WORDS = 2048,
    parameter [31:0]  BASE_ADDR   = 32'h2000_0000,
    parameter integer BURST_BEATS = 16
) (
    input  wire         axi_clk,
    input  wire         axi_rst,
    input  wire         calib_done,

    input  wire [31:0]  s_tdata,
    input  wire         s_tvalid,
    output wire         s_tready,

    output wire [31:0]  m_tdata,
    output wire         m_tvalid,
    input  wire         m_tready,

    output wire [31:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    output wire [127:0] m_axi_wdata,
    output wire [15:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,

    output wire [31:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    output wire [31:0]  used_words,
    output wire         overflow_sticky
);

    localparam integer BURST_WORDS = BURST_BEATS * 4;
    localparam integer IDX_W       = $clog2(DEPTH_WORDS);

    localparam [2:0] W_IDLE   = 3'd0;
    localparam [2:0] W_GATHER = 3'd1;
    localparam [2:0] W_AW     = 3'd2;
    localparam [2:0] W_W      = 3'd3;
    localparam [2:0] W_B      = 3'd4;

    localparam [1:0] R_IDLE   = 2'd0;
    localparam [1:0] R_AR     = 2'd1;
    localparam [1:0] R_R      = 2'd2;
    localparam [1:0] R_UNPACK = 2'd3;

    (* ram_style = "distributed" *) reg [31:0] wr_mem [0:BURST_WORDS-1];
    (* ram_style = "distributed" *) reg [31:0] rd_mem [0:BURST_WORDS-1];

    reg [2:0]  w_st;
    reg [1:0]  r_st;
    reg [IDX_W-1:0] wr_idx, rd_idx;
    reg [31:0] used;
    reg [6:0]  gath_n;
    reg [4:0]  w_beat, r_beat;
    reg [6:0]  unpack_n;
    reg        ovf;

    wire space_ok = (used + BURST_WORDS[31:0] <= DEPTH_WORDS[31:0]);
    wire data_ok  = (used >= BURST_WORDS[31:0]);
    wire live     = calib_done && !axi_rst;

    assign s_tready = live && (w_st == W_GATHER) && (gath_n < BURST_WORDS[6:0]);

    assign m_tvalid = live && (r_st == R_UNPACK);
    assign m_tdata  = rd_mem[unpack_n[5:0]];

    wire [31:0] wr_byte = BASE_ADDR + { {(32-IDX_W-2){1'b0}}, wr_idx, 2'b00 };
    wire [31:0] rd_byte = BASE_ADDR + { {(32-IDX_W-2){1'b0}}, rd_idx, 2'b00 };

    assign m_axi_awaddr  = wr_byte;
    assign m_axi_awlen   = BURST_BEATS[7:0] - 8'd1;
    assign m_axi_awsize  = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awvalid = live && (w_st == W_AW);

    wire [6:0] woff = {w_beat, 2'b00};
    assign m_axi_wdata  = {wr_mem[woff+7'd3], wr_mem[woff+7'd2],
                           wr_mem[woff+7'd1], wr_mem[woff+7'd0]};
    assign m_axi_wstrb  = 16'hFFFF;
    assign m_axi_wlast  = (w_beat == BURST_BEATS[4:0] - 5'd1);
    assign m_axi_wvalid = live && (w_st == W_W);
    assign m_axi_bready = live && (w_st == W_B);

    assign m_axi_araddr  = rd_byte;
    assign m_axi_arlen   = BURST_BEATS[7:0] - 8'd1;
    assign m_axi_arsize  = 3'd4;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arvalid = live && (r_st == R_AR);
    assign m_axi_rready  = live && (r_st == R_R);

    assign used_words       = used;
    assign overflow_sticky  = ovf;

    (* keep = "true" *) wire [1:0] bresp_keep = m_axi_bresp;
    (* keep = "true" *) wire [1:0] rresp_keep = m_axi_rresp;

    always @(posedge axi_clk) begin
        if (axi_rst || !calib_done) begin
            w_st    <= W_IDLE;
            gath_n  <= 7'd0;
            w_beat  <= 5'd0;
            wr_idx  <= {IDX_W{1'b0}};
        end else begin
            if (s_tvalid && s_tready) begin
                wr_mem[gath_n[5:0]] <= s_tdata;
                gath_n <= gath_n + 7'd1;
            end

            case (w_st)
                W_IDLE: begin
                    gath_n <= 7'd0;
                    if (space_ok)
                        w_st <= W_GATHER;
                end
                W_GATHER: begin
                    if (gath_n == BURST_WORDS[6:0])
                        w_st <= W_AW;
                end
                W_AW: begin
                    if (m_axi_awready) begin
                        w_beat <= 5'd0;
                        w_st   <= W_W;
                    end
                end
                W_W: begin
                    if (m_axi_wready) begin
                        if (m_axi_wlast)
                            w_st <= W_B;
                        else
                            w_beat <= w_beat + 5'd1;
                    end
                end
                W_B: begin
                    if (m_axi_bvalid) begin
                        wr_idx <= wr_idx + BURST_WORDS[IDX_W-1:0];
                        w_st   <= W_IDLE;
                    end
                end
                default: w_st <= W_IDLE;
            endcase
        end
    end

    always @(posedge axi_clk) begin
        if (axi_rst || !calib_done) begin
            r_st     <= R_IDLE;
            r_beat   <= 5'd0;
            unpack_n <= 7'd0;
            rd_idx   <= {IDX_W{1'b0}};
        end else begin
            case (r_st)
                R_IDLE: begin
                    if (data_ok) begin
                        r_st   <= R_AR;
                        r_beat <= 5'd0;
                    end
                end
                R_AR: begin
                    if (m_axi_arready)
                        r_st <= R_R;
                end
                R_R: begin
                    if (m_axi_rvalid) begin
                        rd_mem[{r_beat, 2'b00} + 7'd0] <= m_axi_rdata[31:0];
                        rd_mem[{r_beat, 2'b00} + 7'd1] <= m_axi_rdata[63:32];
                        rd_mem[{r_beat, 2'b00} + 7'd2] <= m_axi_rdata[95:64];
                        rd_mem[{r_beat, 2'b00} + 7'd3] <= m_axi_rdata[127:96];
                        r_beat <= r_beat + 5'd1;
                        if (m_axi_rlast) begin
                            rd_idx   <= rd_idx + BURST_WORDS[IDX_W-1:0];
                            unpack_n <= 7'd0;
                            r_st     <= R_UNPACK;
                        end
                    end
                end
                R_UNPACK: begin
                    if (m_tready) begin
                        if (unpack_n == BURST_WORDS[6:0] - 7'd1)
                            r_st <= R_IDLE;
                        unpack_n <= unpack_n + 7'd1;
                    end
                end
                default: r_st <= R_IDLE;
            endcase
        end
    end

    wire wr_commit = (w_st == W_B) && m_axi_bvalid;
    wire rd_commit = (r_st == R_R) && m_axi_rvalid && m_axi_rlast;

    always @(posedge axi_clk) begin
        if (axi_rst || !calib_done) begin
            used <= 32'd0;
            ovf  <= 1'b0;
        end else begin
            case ({wr_commit, rd_commit})
                2'b10: used <= used + BURST_WORDS[31:0];
                2'b01: used <= used - BURST_WORDS[31:0];
                default: ;
            endcase
            if (s_tvalid && !s_tready && live)
                ovf <= 1'b1;
        end
    end

endmodule
