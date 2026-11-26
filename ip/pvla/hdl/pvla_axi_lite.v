`timescale 1ns / 1ps
// AXI4-Lite slave for PVLA. Lives in s_axi_aclk.
// Writes to CMD (0x00) toggle a CDC handshake into the capture domain.
// Status/counters are sampled with a 2FF CDC of 1-bit flags; counters may
// be one capture-clock stale (host/CPU polling, not sample-accurate).
module pvla_axi_lite (
    input  wire        s_axi_aclk,
    input  wire        s_axi_aresetn,

    input  wire [7:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [7:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // Capture-domain handshake
    input  wire        cap_clk,
    input  wire        cap_rst,
    output wire        cmd_valid,
    output wire [31:0] cmd_data,
    input  wire        armed,
    input  wire        triggered,
    input  wire        cap_done,
    input  wire        overflow_sticky,
    input  wire [1:0]  source_sel,
    input  wire [31:0] overflow_cnt,
    input  wire [31:0] drop_cnt
);

    localparam [7:0] REG_CMD    = 8'h00;
    localparam [7:0] REG_STATUS = 8'h04;
    localparam [7:0] REG_OVF    = 8'h08;
    localparam [7:0] REG_DROP   = 8'h0C;
    localparam [7:0] REG_IDENT  = 8'h10;
    localparam [31:0] IDENT     = 32'h414C5650; // "PVLA"

    // ── write channel ────────────────────────────────────────────
    reg        awready_r, wready_r, bvalid_r;
    reg [7:0]  awaddr_r;
    reg        aw_got, w_got;
    reg [31:0] wdata_r;
    reg [3:0]  wstrb_r;

    assign s_axi_awready = awready_r;
    assign s_axi_wready  = wready_r;
    assign s_axi_bvalid  = bvalid_r;
    assign s_axi_bresp   = 2'b00;

    wire wr_fire = aw_got && w_got && !bvalid_r;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            awready_r <= 1'b0;
            wready_r  <= 1'b0;
            bvalid_r  <= 1'b0;
            aw_got    <= 1'b0;
            w_got     <= 1'b0;
            awaddr_r  <= 8'h00;
            wdata_r   <= 32'h0;
            wstrb_r   <= 4'h0;
        end else begin
            awready_r <= 1'b0;
            wready_r  <= 1'b0;

            if (!aw_got && !awready_r && s_axi_awvalid) begin
                awready_r <= 1'b1;
                aw_got    <= 1'b1;
                awaddr_r  <= s_axi_awaddr;
            end
            if (!w_got && !wready_r && s_axi_wvalid) begin
                wready_r <= 1'b1;
                w_got    <= 1'b1;
                wdata_r  <= s_axi_wdata;
                wstrb_r  <= s_axi_wstrb;
            end
            if (wr_fire) begin
                bvalid_r <= 1'b1;
                aw_got   <= 1'b0;
                w_got    <= 1'b0;
            end
            if (bvalid_r && s_axi_bready)
                bvalid_r <= 1'b0;
        end
    end

    wire wr_cmd = wr_fire && (awaddr_r[7:2] == REG_CMD[7:2]);

    // ── CMD CDC: axi clk → capture clk ───────────────────────────
    reg [31:0] cmd_hold;
    reg        cmd_tog_axi;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            cmd_hold    <= 32'h0;
            cmd_tog_axi <= 1'b0;
        end else if (wr_cmd) begin
            cmd_hold[7:0]   <= wstrb_r[0] ? wdata_r[7:0]   : cmd_hold[7:0];
            cmd_hold[15:8]  <= wstrb_r[1] ? wdata_r[15:8]  : cmd_hold[15:8];
            cmd_hold[23:16] <= wstrb_r[2] ? wdata_r[23:16] : cmd_hold[23:16];
            cmd_hold[31:24] <= wstrb_r[3] ? wdata_r[31:24] : cmd_hold[31:24];
            cmd_tog_axi     <= ~cmd_tog_axi;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [2:0] cmd_tog_cap;
    always @(posedge cap_clk) begin
        if (cap_rst)
            cmd_tog_cap <= 3'b000;
        else
            cmd_tog_cap <= {cmd_tog_cap[1:0], cmd_tog_axi};
    end

    assign cmd_valid = cmd_tog_cap[2] ^ cmd_tog_cap[1];
    assign cmd_data  = cmd_hold;

    // ── status CDC: capture → axi ────────────────────────────────
    (* ASYNC_REG = "TRUE" *) reg [1:0] armed_s, trig_s, done_s, ovf_s;
    (* ASYNC_REG = "TRUE" *) reg [1:0] src0_s, src1_s;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            armed_s <= 2'b00;
            trig_s  <= 2'b00;
            done_s  <= 2'b00;
            ovf_s   <= 2'b00;
            src0_s  <= 2'b00;
            src1_s  <= 2'b00;
        end else begin
            armed_s <= {armed_s[0], armed};
            trig_s  <= {trig_s[0],  triggered};
            done_s  <= {done_s[0],  cap_done};
            ovf_s   <= {ovf_s[0],   overflow_sticky};
            src0_s  <= {src0_s[0],  source_sel[0]};
            src1_s  <= {src1_s[0],  source_sel[1]};
        end
    end

    // Multi-bit counters: sample without gray (status poll only).
    (* ASYNC_REG = "TRUE" *) reg [31:0] ovf_cnt_s, drop_cnt_s;
    always @(posedge s_axi_aclk) begin
        ovf_cnt_s  <= overflow_cnt;
        drop_cnt_s <= drop_cnt;
    end

    wire [31:0] status_w = {
        24'h0,
        2'b00,
        src1_s[1], src0_s[1],
        ovf_s[1], done_s[1], trig_s[1], armed_s[1]
    };

    // ── read channel ─────────────────────────────────────────────
    reg        arready_r, rvalid_r;
    reg [31:0] rdata_r;

    assign s_axi_arready = arready_r;
    assign s_axi_rvalid  = rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = 2'b00;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            arready_r <= 1'b0;
            rvalid_r  <= 1'b0;
            rdata_r   <= 32'h0;
        end else begin
            arready_r <= 1'b0;
            if (!arready_r && s_axi_arvalid && !rvalid_r) begin
                arready_r <= 1'b1;
                rvalid_r  <= 1'b1;
                case (s_axi_araddr[7:2])
                    REG_CMD[7:2]:    rdata_r <= cmd_hold;
                    REG_STATUS[7:2]: rdata_r <= status_w;
                    REG_OVF[7:2]:    rdata_r <= ovf_cnt_s;
                    REG_DROP[7:2]:   rdata_r <= drop_cnt_s;
                    REG_IDENT[7:2]:  rdata_r <= IDENT;
                    default:         rdata_r <= 32'h0;
                endcase
            end
            if (rvalid_r && s_axi_rready)
                rvalid_r <= 1'b0;
        end
    end

endmodule
