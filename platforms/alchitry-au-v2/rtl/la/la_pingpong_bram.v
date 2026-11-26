`timescale 1ns / 1ps
// Two 4 KiB BRAM banks (1024 x 32-bit) in front of the PR #18 PHY.
//
// Fill never looks at TXE. The sampler writes the fill bank every clock
// until that bank is full, then swaps. Dump presents a whole 4 KiB burst
// to ft601_sync_fifo (TX_BURST_WORDS=1024). TXE only pauses the dump.
//
// wr_ready drops only when both banks are occupied — overflow, not TXE.
// dout + combinational lookahead address so each word is dumped once
// (the echo BRAM alignment bug was a duplicate first word).
module la_pingpong_bram #(
    parameter integer WORDS = 1024
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] wr_data,
    input  wire        wr_valid,
    output wire        wr_ready,

    output wire [31:0] tx_data,
    output wire        tx_valid,
    output wire        tx_last,
    input  wire        tx_ready,

    output reg         overflow_sticky,
    output wire        dump_active,
    output wire [1:0]  banks_full
);

    localparam integer LAST     = WORDS - 1;
    localparam [1:0]   ST_IDLE  = 2'd0;
    localparam [1:0]   ST_PREF0 = 2'd1;
    localparam [1:0]   ST_PREF1 = 2'd2;
    localparam [1:0]   ST_DUMP  = 2'd3;

    (* ram_style = "block" *) reg [31:0] bank0 [0:WORDS-1];
    (* ram_style = "block" *) reg [31:0] bank1 [0:WORDS-1];

    reg             fill_sel;
    reg             dump_sel;
    reg [9:0]       wr_addr;
    reg [9:0]       rd_addr;
    reg [9:0]       beat;
    reg [1:0]       full;
    reg [1:0]       st;
    reg [31:0]      rd0;
    reg [31:0]      rd1;
    reg [31:0]      dout;

    wire [31:0] rd_q    = dump_sel ? rd1 : rd0;
    wire        wr_fire = wr_valid && wr_ready;
    wire        wr_last = wr_fire && (wr_addr == LAST[9:0]);
    wire        bump    = (st == ST_DUMP) && tx_ready && (beat != LAST[9:0]);
    wire [9:0]  bram_rd = bump ? (rd_addr + 10'd1) : rd_addr;

    assign wr_ready    = !full[fill_sel];
    assign banks_full  = full;
    assign dump_active = (st == ST_DUMP);
    assign tx_valid    = (st == ST_DUMP);
    assign tx_last     = (st == ST_DUMP) && (beat == LAST[9:0]);
    assign tx_data     = dout;

    always @(posedge clk) begin
        if (wr_fire && (fill_sel == 1'b0))
            bank0[wr_addr] <= wr_data;
        rd0 <= bank0[bram_rd];
    end

    always @(posedge clk) begin
        if (wr_fire && (fill_sel == 1'b1))
            bank1[wr_addr] <= wr_data;
        rd1 <= bank1[bram_rd];
    end

    always @(posedge clk) begin
        if (rst) begin
            fill_sel        <= 1'b0;
            dump_sel        <= 1'b0;
            wr_addr         <= 10'd0;
            rd_addr         <= 10'd0;
            beat            <= 10'd0;
            full            <= 2'b00;
            st              <= ST_IDLE;
            dout            <= 32'd0;
            overflow_sticky <= 1'b0;
        end else begin
            // Host too slow: both banks full and dump is waiting on TXE.
            // A 2-cycle wrap while dump is popping is not overflow.
            if (wr_valid && !wr_ready && (st == ST_DUMP) && !tx_ready)
                overflow_sticky <= 1'b1;

            if (wr_fire) begin
                if (wr_last) begin
                    wr_addr        <= 10'd0;
                    full[fill_sel] <= 1'b1;
                    fill_sel       <= ~fill_sel;
                end else
                    wr_addr <= wr_addr + 1'b1;
            end

            case (st)
                ST_IDLE: begin
                    if (full[dump_sel]) begin
                        rd_addr <= 10'd0;
                        st      <= ST_PREF0;
                    end
                end
                ST_PREF0: begin
                    rd_addr <= 10'd1;
                    st      <= ST_PREF1;
                end
                ST_PREF1: begin
                    dout <= rd_q;
                    beat <= 10'd0;
                    st   <= ST_DUMP;
                end
                ST_DUMP: begin
                    if (tx_ready) begin
                        if (beat == LAST[9:0]) begin
                            full[dump_sel] <= 1'b0;
                            dump_sel       <= ~dump_sel;
                            rd_addr        <= 10'd0;
                            beat           <= 10'd0;
                            st             <= ST_IDLE;
                        end else begin
                            dout    <= rd_q;
                            beat    <= beat + 1'b1;
                            rd_addr <= rd_addr + 1'b1;
                        end
                    end
                end
                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
