`timescale 1ns / 1ps
// Two 4 KiB banks as one 8 KiB FWFT FIFO in front of the PR #18 PHY.
// Sampler enable is wr_ready (occupancy), never TXE.
//
// Synth: two FIFO36E1 FWFT cascaded (1024x32 each). Icarus: behavioral
// dual-BRAM with the same ports. Live TXE only pops the dump word; ADDRB
// lives inside the FIFO primitive.
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

`ifdef ICARUS
    localparam integer DEPTH = WORDS * 2;

    (* ram_style = "block" *) reg [31:0] bank0 [0:WORDS-1];
    (* ram_style = "block" *) reg [31:0] bank1 [0:WORDS-1];

    reg [10:0] wa;
    reg [10:0] ra;
    reg [11:0] used;
    reg [11:0] mem_used;
    reg        s1_v, s2_v;
    reg [31:0] s1, s2;
    reg [31:0] rd0, rd1;
    reg        rsel;
    reg        issue_d;
    reg [9:0]  beat;

    wire        push     = wr_valid && wr_ready;
    wire        pop      = s2_v && tx_ready;
    wire        take2    = !s2_v || pop;
    wire        s1_room  = ((!s1_v && !issue_d) || take2);
    wire        issue    = (mem_used != 12'd0) && s1_room;
    wire        s1_load  = issue_d && (!take2 || s1_v);
    wire        s2_from1 = take2 && s1_v;
    wire        s2_bypass= take2 && !s1_v && issue_d;
    wire [31:0] ram_q    = rsel ? rd1 : rd0;

    assign wr_ready    = (used != DEPTH[11:0]);
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
            mem_used        <= 12'd0;
            s1_v            <= 1'b0;
            s2_v            <= 1'b0;
            s1              <= 32'd0;
            s2              <= 32'd0;
            rsel            <= 1'b0;
            issue_d         <= 1'b0;
            beat            <= 10'd0;
            overflow_sticky <= 1'b0;
        end else begin
            if (wr_valid && !wr_ready && s2_v)
                overflow_sticky <= 1'b1;

            if (push)
                wa <= wa + 11'd1;

            case ({push, pop})
                2'b10: used <= used + 12'd1;
                2'b01: used <= used - 12'd1;
                default: ;
            endcase

            if (push && !issue)
                mem_used <= mem_used + 12'd1;
            else if (!push && issue && (mem_used != 12'd0))
                mem_used <= mem_used - 12'd1;

            rsel    <= ra[10];
            issue_d <= issue;
            if (issue && (mem_used != 12'd0))
                ra <= ra + 11'd1;

            if (s1_load)
                s1 <= ram_q;

            if (s2_from1) begin
                s2   <= s1;
                s2_v <= 1'b1;
            end else if (s2_bypass) begin
                s2   <= ram_q;
                s2_v <= 1'b1;
            end else if (take2) begin
                s2_v <= 1'b0;
            end

            if (s1_load)
                s1_v <= 1'b1;
            else if (take2)
                s1_v <= 1'b0;

            if (pop)
                beat <= beat + 10'd1;
        end
    end
`else
    wire        full0, empty0, full1, empty1;
    wire [31:0] mid;
    wire        push = wr_valid && !full0;
    wire        xfer = !empty0 && !full1;
    wire        pop  = !empty1 && tx_ready;
    reg  [9:0]  beat;

    assign wr_ready    = !full0;
    assign tx_valid    = !empty1;
    assign dump_active = !empty1 || !empty0;
    assign banks_full  = {full0 || full1, full0 && full1};
    assign tx_last     = tx_valid && (beat == 10'd1023);

    la_fifo36_fwft u_f0 (
        .clk   (clk),
        .rst   (rst),
        .din   (wr_data),
        .wr_en (push),
        .full  (full0),
        .dout  (mid),
        .rd_en (xfer),
        .empty (empty0)
    );

    la_fifo36_fwft u_f1 (
        .clk   (clk),
        .rst   (rst),
        .din   (mid),
        .wr_en (xfer),
        .full  (full1),
        .dout  (tx_data),
        .rd_en (pop),
        .empty (empty1)
    );

    always @(posedge clk) begin
        if (rst) begin
            overflow_sticky <= 1'b0;
            beat            <= 10'd0;
        end else begin
            if (wr_valid && full0 && !empty1)
                overflow_sticky <= 1'b1;
            if (pop)
                beat <= beat + 10'd1;
        end
    end
`endif

endmodule
