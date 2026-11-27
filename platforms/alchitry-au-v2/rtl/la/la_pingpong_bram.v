`timescale 1ns / 1ps
// Two 4 KiB BRAM banks (1024 x 32-bit) in front of the PR #18 PHY.
//
// Fill never looks at TXE. Sampler writes the fill bank every clock
// until that bank is full, then swaps. Dump reads a full bank into a
// 4-deep LUT FIFO; the PHY pops that FIFO. TXE only pauses the pop.
// BRAM address is a FF (not combo from live TXE) so 100 MHz can close.
//
// wr_ready drops only when both banks are occupied — overflow, not TXE.
// full0/full1 are separate bits (variable-index full[sel] NBA is a Vivado
// synthesis footgun).
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

    localparam integer LAST    = WORDS - 1;
    localparam [1:0]   ST_IDLE = 2'd0;
    localparam [1:0]   ST_PREF = 2'd1;
    localparam [1:0]   ST_DUMP = 2'd2;

    (* ram_style = "block" *) reg [31:0] bank0 [0:WORDS-1];
    (* ram_style = "block" *) reg [31:0] bank1 [0:WORDS-1];

    (* ram_style = "distributed" *) reg [31:0] fifo [0:3];
    reg [3:0]       fifo_last;
    reg [1:0]       fifo_w;
    reg [1:0]       fifo_r;
    reg [2:0]       fifo_n;

    reg             fill_sel;
    reg             dump_sel;
    reg [9:0]       wr_addr;
    reg [9:0]       rd_addr;
    reg [9:0]       dumped;
    reg             full0;
    reg             full1;
    (* fsm_encoding = "none" *) reg [1:0] st;
    reg             dump_q;
    reg [31:0]      rd0;
    reg [31:0]      rd1;

    wire [31:0] rd_q      = dump_sel ? rd1 : rd0;
    wire        wr_fire   = wr_valid && wr_ready;
    wire        wr_last   = wr_fire && (wr_addr == LAST[9:0]);
    wire        dump_full = dump_sel ? full1 : full0;
    wire        fifo_full  = (fifo_n == 3'd4);
    wire        fifo_empty = (fifo_n == 3'd0);
    wire        fifo_push  = dump_q && !fifo_full;
    wire        fifo_pop   = !fifo_empty && tx_ready;
    wire        dump_last  = fifo_push && (dumped == LAST[9:0]);
    // Lookahead is fifo occupancy, not live TXE, so ADDRB is off the IOB budget.
    wire [9:0]  bram_rd    = fifo_push ? (rd_addr + 10'd1) : rd_addr;

    assign wr_ready    = fill_sel ? ~full1 : ~full0;
    assign banks_full  = {full1, full0};
    assign dump_active = dump_q || !fifo_empty;
    assign tx_valid    = !fifo_empty;
    assign tx_data     = fifo[fifo_r];
    assign tx_last     = !fifo_empty && fifo_last[fifo_r];

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
            dumped          <= 10'd0;
            full0           <= 1'b0;
            full1           <= 1'b0;
            st              <= ST_IDLE;
            dump_q          <= 1'b0;
            fifo_w          <= 2'd0;
            fifo_r          <= 2'd0;
            fifo_n          <= 3'd0;
            fifo_last       <= 4'd0;
            overflow_sticky <= 1'b0;
        end else begin
            if (wr_valid && !wr_ready && dump_q)
                overflow_sticky <= 1'b1;

            if (wr_fire) begin
                if (wr_last) begin
                    wr_addr <= 10'd0;
                    if (fill_sel)
                        full1 <= 1'b1;
                    else
                        full0 <= 1'b1;
                    fill_sel <= ~fill_sel;
                end else
                    wr_addr <= wr_addr + 1'b1;
            end

            if (fifo_push) begin
                fifo[fifo_w] <= rd_q;
                fifo_last[fifo_w] <= dump_last;
                fifo_w <= fifo_w + 2'd1;
            end
            if (fifo_pop)
                fifo_r <= fifo_r + 2'd1;
            case ({fifo_push, fifo_pop})
                2'b10: fifo_n <= fifo_n + 3'd1;
                2'b01: fifo_n <= fifo_n - 3'd1;
                default: ;
            endcase

            case (st)
                ST_IDLE: begin
                    dump_q <= 1'b0;
                    if (dump_full) begin
                        rd_addr <= 10'd0;
                        dumped  <= 10'd0;
                        st      <= ST_PREF;
                    end
                end
                ST_PREF: begin
                    dump_q <= 1'b1;
                    st     <= ST_DUMP;
                end
                ST_DUMP: begin
                    if (fifo_push) begin
                        if (dump_last) begin
                            if (dump_sel)
                                full1 <= 1'b0;
                            else
                                full0 <= 1'b0;
                            dump_sel <= ~dump_sel;
                            dump_q   <= 1'b0;
                            dumped   <= 10'd0;
                            rd_addr  <= 10'd0;
                            st       <= ST_IDLE;
                        end else begin
                            rd_addr <= rd_addr + 1'b1;
                            dumped  <= dumped + 1'b1;
                        end
                    end
                end
                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
