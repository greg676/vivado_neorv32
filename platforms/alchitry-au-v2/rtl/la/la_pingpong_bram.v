`timescale 1ns / 1ps
// Two 4 KiB BRAM banks (1024 x 32) as one 8 KiB show-ahead FIFO
// in front of the PR #18 PHY.
//
// Fill never looks at TXE. wr_ready drops only when both banks are
// occupied (used == 2048), and while draining a dual-full. Dump pops
// the output register. Occupancy is one adder. BRAM reads are always-on
// (read CE synthesized empty on this part). tx_valid is a FF.
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

    localparam integer DEPTH = WORDS * 2;

    (* ram_style = "block" *) reg [31:0] bank0 [0:WORDS-1];
    (* ram_style = "block" *) reg [31:0] bank1 [0:WORDS-1];

    reg [10:0] wa;
    reg [10:0] ra;
    reg [11:0] used;
    reg        s1_v, s2_v;
    reg [31:0] s1, s2;
    reg [31:0] rd0, rd1;
    reg        rsel;
    reg        issue_d;
    reg [9:0]  beat;
    reg        drain_full;

    wire        push    = wr_valid && wr_ready;
    wire        pop     = s2_v && tx_ready;
    wire        take2   = !s2_v || pop;
    wire [2:0]  occ     = {2'b0, s1_v} + {2'b0, s2_v} + {2'b0, issue_d};
    wire [2:0]  occ_nxt = pop ? (occ - 3'd1) : occ;
    wire        issue   = (used > {9'd0, occ}) && (occ_nxt < 3'd2);
    wire [31:0] ram_q   = rsel ? rd1 : rd0;

    assign wr_ready    = (used != DEPTH[11:0]) && !drain_full;
    assign banks_full  = {used >= WORDS[11:0], used == DEPTH[11:0]};
    assign dump_active = s2_v || s1_v;
    assign tx_valid    = s2_v;
    assign tx_data     = s2;
    assign tx_last     = s2_v && (beat == 10'd1023);

    always @(posedge clk) begin
        if (push && (wa[10] == 1'b0))
            bank0[wa[9:0]] <= wr_data;
        rd0 <= bank0[ra[9:0]];
    end

    always @(posedge clk) begin
        if (push && (wa[10] == 1'b1))
            bank1[wa[9:0]] <= wr_data;
        rd1 <= bank1[ra[9:0]];
    end

    always @(posedge clk) begin
        if (rst) begin
            wa              <= 11'd0;
            ra              <= 11'd0;
            used            <= 12'd0;
            s1_v            <= 1'b0;
            s2_v            <= 1'b0;
            s1              <= 32'd0;
            s2              <= 32'd0;
            rsel            <= 1'b0;
            issue_d         <= 1'b0;
            beat            <= 10'd0;
            drain_full      <= 1'b0;
            overflow_sticky <= 1'b0;
        end else begin
            if (used == DEPTH[11:0])
                drain_full <= 1'b1;
            else if (used == 12'd0)
                drain_full <= 1'b0;

            if (wr_valid && !wr_ready && s2_v)
                overflow_sticky <= 1'b1;

            if (push)
                wa <= wa + 11'd1;

            case ({push, pop})
                2'b10: used <= used + 12'd1;
                2'b01: used <= used - 12'd1;
                default: ;
            endcase

            rsel    <= ra[10];
            issue_d <= issue;
            if (issue)
                ra <= ra + 11'd1;

            if (issue_d)
                s1 <= ram_q;

            if (take2) begin
                if (s1_v) begin
                    s2   <= s1;
                    s2_v <= 1'b1;
                end else
                    s2_v <= 1'b0;
            end

            if (issue_d)
                s1_v <= 1'b1;
            else if (take2)
                s1_v <= 1'b0;

            if (pop)
                beat <= beat + 10'd1;
        end
    end

endmodule
