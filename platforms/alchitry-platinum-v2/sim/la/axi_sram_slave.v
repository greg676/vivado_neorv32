`timescale 1ns / 1ps
// Behavioral 128-bit AXI4 slave standing in for MIG7. Sim only.
// INCR bursts, single outstanding write and read. Byte address BASE_ADDR.
module axi_sram_slave #(
    parameter integer DEPTH_WORDS = 2048,
    parameter [31:0]  BASE_ADDR   = 32'h2000_0000
) (
    input  wire         clk,
    input  wire         rst,

    input  wire [31:0]  s_axi_awaddr,
    input  wire [7:0]   s_axi_awlen,
    input  wire [2:0]   s_axi_awsize,
    input  wire [1:0]   s_axi_awburst,
    input  wire         s_axi_awvalid,
    output reg          s_axi_awready,
    input  wire [127:0] s_axi_wdata,
    input  wire [15:0]  s_axi_wstrb,
    input  wire         s_axi_wlast,
    input  wire         s_axi_wvalid,
    output reg          s_axi_wready,
    output reg  [1:0]   s_axi_bresp,
    output reg          s_axi_bvalid,
    input  wire         s_axi_bready,

    input  wire [31:0]  s_axi_araddr,
    input  wire [7:0]   s_axi_arlen,
    input  wire [2:0]   s_axi_arsize,
    input  wire [1:0]   s_axi_arburst,
    input  wire         s_axi_arvalid,
    output reg          s_axi_arready,
    output reg  [127:0] s_axi_rdata,
    output reg  [1:0]   s_axi_rresp,
    output reg          s_axi_rlast,
    output reg          s_axi_rvalid,
    input  wire         s_axi_rready
);

    localparam integer BEATS = DEPTH_WORDS / 4;

    reg [127:0] mem [0:BEATS-1];
    integer     i;

    reg [31:0] waddr, raddr;
    reg [7:0]  wleft, rleft;
    reg        w_busy, r_busy;

    function automatic [31:0] beat_idx;
        input [31:0] addr;
        begin
            beat_idx = (addr - BASE_ADDR) >> 4;
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rlast   <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 128'd0;
            w_busy        <= 1'b0;
            r_busy        <= 1'b0;
            wleft         <= 8'd0;
            rleft         <= 8'd0;
            waddr         <= 32'd0;
            raddr         <= 32'd0;
        end else begin
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (!w_busy && s_axi_awvalid && s_axi_awready) begin
                waddr         <= s_axi_awaddr;
                wleft         <= s_axi_awlen;
                w_busy        <= 1'b1;
                s_axi_awready <= 1'b0;
                s_axi_wready  <= 1'b1;
            end else if (w_busy && s_axi_wvalid && s_axi_wready) begin
                if (s_axi_wstrb == 16'hFFFF)
                    mem[beat_idx(waddr)] <= s_axi_wdata;
                else begin
                    for (i = 0; i < 16; i = i + 1)
                        if (s_axi_wstrb[i])
                            mem[beat_idx(waddr)][i*8 +: 8] <= s_axi_wdata[i*8 +: 8];
                end
                waddr <= waddr + 32'd16;
                if (s_axi_wlast || (wleft == 8'd0)) begin
                    w_busy        <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b1;
                    s_axi_bresp   <= 2'b00;
                    s_axi_awready <= 1'b1;
                end else
                    wleft <= wleft - 8'd1;
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
                if (s_axi_rlast) begin
                    r_busy        <= 1'b0;
                    s_axi_arready <= 1'b1;
                end
            end

            if (!r_busy && s_axi_arvalid && s_axi_arready) begin
                raddr         <= s_axi_araddr;
                rleft         <= s_axi_arlen;
                r_busy        <= 1'b1;
                s_axi_arready <= 1'b0;
            end else if (r_busy && !s_axi_rvalid) begin
                s_axi_rdata  <= mem[beat_idx(raddr)];
                s_axi_rresp  <= 2'b00;
                s_axi_rvalid <= 1'b1;
                s_axi_rlast  <= (rleft == 8'd0);
                raddr        <= raddr + 32'd16;
                if (rleft != 8'd0)
                    rleft <= rleft - 8'd1;
            end
        end
    end

    (* keep = "true" *) wire [2:0] awsize_k = s_axi_awsize;
    (* keep = "true" *) wire [1:0] awburst_k = s_axi_awburst;
    (* keep = "true" *) wire [2:0] arsize_k = s_axi_arsize;
    (* keep = "true" *) wire [1:0] arburst_k = s_axi_arburst;

endmodule
