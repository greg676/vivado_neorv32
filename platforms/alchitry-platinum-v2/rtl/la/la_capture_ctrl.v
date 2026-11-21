`timescale 1ns / 1ps
// Triggered capture controller: host start/stop, edge trigger, BRAM
// circular pre-trigger, post-trigger count, overflow/drop counters,
// dump header with trigger position.
//
// Host command (one 32-bit FT601 RX word):
//   [3:0]   cmd     0 nop, 1 cfg, 2 start, 3 stop, 4 force
//   [5:4]   source  0 counter, 1 walking, 2 live
//   [8:6]   trig_ch 0-7
//   [10:9]  edge    0 rise, 1 fall, 2 both, 3 immediate
//   [31:16] post_n  samples after trigger (0 = keep current / default)
//
// Dump (little-endian 32-bit words, then packed samples):
//   0 MAGIC      32'h3354414C  ("LAT3")
//   1 VERSION    1
//   2 STATUS     [1:0] source [4:2] ch [6:5] edge
//                [8] triggered [9] overflow [10] aborted [11] immediate
//   3 NSAMPLES   8-bit samples in the payload (zero-pad to a 4-sample word
//                is not counted here)
//   4 TRIG_POS   sample index of trigger, or 32'hFFFFFFFF if none
//   5 OVERFLOW   samples overwritten during POST (lost pre-trigger)
//   6 DROP       samples not captured (STOP before post_n, or clobber stop)
//   7 POST_CFG   configured post-trigger sample count
module la_capture_ctrl #(
    parameter integer SAMPLE_MHZ     = 100,
    parameter [1:0]   DEFAULT_SOURCE = 2'd0,
    parameter integer BUF_DEPTH      = 4096,
    parameter integer ADDR_W         = 12,
    parameter integer DEFAULT_POST   = 2048,
    parameter [2:0]   DEFAULT_CH     = 3'd0,
    parameter [1:0]   DEFAULT_EDGE   = 2'd0
) (
    input  wire        clk,
    input  wire        rst,

    input  wire [7:0]  s0,
    input  wire [7:0]  s1,

    input  wire        rx_valid,
    input  wire [31:0] rx_data,

    output wire [1:0]  source_sel,
    output wire        pattern_en,
    output wire        pattern_rst,

    output wire [7:0]  pack_s0,
    output wire [7:0]  pack_s1,
    output wire        pack_en,
    input  wire [31:0] pack_data,
    input  wire        pack_valid,

    output wire [31:0] fifo_wdata,
    output wire        fifo_wr,
    input  wire        fifo_full,
    input  wire        fifo_almost_full,

    output wire        armed,
    output wire        triggered_o,
    output wire        cap_done,
    output wire        overflow_sticky,
    output wire [31:0] overflow_cnt,
    output wire [31:0] drop_cnt
);

    localparam integer SAMP_PER = (SAMPLE_MHZ == 200) ? 2 : 1;

    localparam [3:0] CMD_CFG   = 4'd1;
    localparam [3:0] CMD_START = 4'd2;
    localparam [3:0] CMD_STOP  = 4'd3;
    localparam [3:0] CMD_FORCE = 4'd4;

    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_ARM  = 3'd1;
    localparam [2:0] ST_POST = 3'd2;
    localparam [2:0] ST_HDR  = 3'd3;
    localparam [2:0] ST_DUMP = 3'd4;
    localparam [2:0] ST_DONE = 3'd5;

    localparam [31:0] HDR_MAGIC = 32'h3354414C;
    localparam [31:0] HDR_VER   = 32'h00000001;
    localparam [1:0]  EDGE_IMM  = 2'd3;

    // ── command / config ─────────────────────────────────────────
    reg [2:0]  state;
    reg [1:0]  src_r;
    reg [2:0]  ch_r;
    reg [1:0]  edge_r;
    reg [15:0] post_n;

    wire [3:0] cmd_w     = rx_data[3:0];
    wire       busy_dump = (state == ST_HDR) || (state == ST_DUMP);
    wire       cmd_go    = rx_valid && !busy_dump;
    wire       do_cfg    = cmd_go && (cmd_w == CMD_CFG);
    wire       do_start  = cmd_go && (cmd_w == CMD_START);
    wire       do_stop   = cmd_go && (cmd_w == CMD_STOP);
    wire       do_force  = cmd_go && (cmd_w == CMD_FORCE) && (state == ST_ARM);

    wire [1:0] src_now  = (do_start || do_cfg) ? rx_data[5:4]  : src_r;
    wire [2:0] ch_now   = (do_start || do_cfg) ? rx_data[8:6]  : ch_r;
    wire [1:0] edge_now = (do_start || do_cfg) ? rx_data[10:9] : edge_r;

    assign source_sel  = src_now;
    wire   capturing   = (state == ST_ARM) || (state == ST_POST);
    assign pattern_en  = capturing;
    assign pattern_rst = do_start;

    always @(posedge clk) begin
        if (rst) begin
            src_r  <= DEFAULT_SOURCE;
            ch_r   <= DEFAULT_CH;
            edge_r <= DEFAULT_EDGE;
            post_n <= DEFAULT_POST[15:0];
        end else if (do_start || do_cfg) begin
            src_r  <= rx_data[5:4];
            ch_r   <= rx_data[8:6];
            edge_r <= rx_data[10:9];
            if (rx_data[31:16] != 16'd0)
                post_n <= rx_data[31:16];
        end
    end

    // ── trigger ──────────────────────────────────────────────────
    wire trig_hit;
    wire trig_s1;
    la_trig #(
        .SAMPLE_MHZ(SAMPLE_MHZ)
    ) u_trig (
        .clk       (clk),
        .rst       (rst),
        .enable    (capturing),
        .s0        (s0),
        .s1        (s1),
        .channel   (ch_now),
        .edge_mode (edge_now),
        .hit       (trig_hit),
        .hit_s1    (trig_s1)
    );

    wire hit      = capturing && (trig_hit || do_force);
    wire hit_s1_w = trig_hit ? trig_s1 : 1'b0;

    // ── circular BRAM pointers ───────────────────────────────────
    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W:0]   filled;
    reg [ADDR_W-1:0] trig_addr;
    reg              trig_s1_r;
    reg              triggered_r;
    reg              aborted_r;
    reg [31:0]       overflow_r;
    reg [31:0]       drop_r;
    reg [31:0]       post_got;

    wire would_clobber = (state == ST_POST) &&
                         (filled == BUF_DEPTH[ADDR_W:0]) &&
                         (wr_ptr == trig_addr);
    wire post_done = (state == ST_POST) && (post_got >= {16'd0, post_n});
    wire wr_fire   = capturing && !would_clobber && !post_done;

    wire [15:0] wr_word = (SAMPLE_MHZ == 200) ? {s1, s0} : {8'h00, s0};

    // ── dump / header ────────────────────────────────────────────
    reg [2:0]        hdr_idx;
    reg              hdr_loaded;
    reg [31:0]       hdr_nsamp;
    reg [31:0]       hdr_tpos;
    reg [31:0]       hdr_ovf;
    reg [31:0]       hdr_drop;
    reg [15:0]       hdr_post;
    reg              hdr_trig;
    reg              hdr_aborted;
    reg [1:0]        hdr_src;
    reg [2:0]        hdr_ch;
    reg [1:0]        hdr_edge;
    reg [ADDR_W-1:0] dump_start;
    reg [ADDR_W:0]   dump_n;
    reg [ADDR_W:0]   rd_issued_cnt;
    reg [31:0]       pay_expect;
    reg [31:0]       pay_got;
    reg              rd_issued;
    reg              skid_valid;
    reg [15:0]       skid_data;
    wire [15:0]      rd_data;

    wire stall = fifo_almost_full || fifo_full;

    wire        bram_valid = rd_issued;
    wire [15:0] dump_word  = skid_valid ? skid_data : rd_data;
    wire        dump_valid = skid_valid || bram_valid;
    wire        dump_take  = (state == ST_DUMP) && dump_valid && !stall;
    wire        can_rd     = (state == ST_DUMP) && (rd_issued_cnt != dump_n) &&
                             !stall && !(skid_valid && !dump_take);
    wire [ADDR_W-1:0] rd_addr = dump_start + rd_issued_cnt[ADDR_W-1:0];

    la_circ_bram #(
        .DEPTH (BUF_DEPTH),
        .ADDR_W(ADDR_W)
    ) u_bram (
        .clk     (clk),
        .wr_en   (wr_fire),
        .wr_addr (wr_ptr),
        .wr_data (wr_word),
        .rd_en   (can_rd),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    wire entries_done = (rd_issued_cnt == dump_n) && !dump_valid && !rd_issued;
    wire pad_take = (state == ST_DUMP) && entries_done &&
                    (pay_got < pay_expect) && !stall;

    assign pack_s0 = dump_take ? dump_word[7:0]  : 8'd0;
    assign pack_s1 = dump_take ? dump_word[15:8] : 8'd0;
    assign pack_en = dump_take || pad_take;

    // [1:0] src [4:2] ch [6:5] edge [7] rsvd
    // [8] triggered [9] overflow [10] aborted [11] immediate
    wire [31:0] status_word = {20'd0,
        (hdr_edge == EDGE_IMM), hdr_aborted, (hdr_ovf != 32'd0), hdr_trig,
        1'b0, hdr_edge, hdr_ch, hdr_src};

    wire [31:0] hdr_word =
        (hdr_idx == 3'd0) ? HDR_MAGIC :
        (hdr_idx == 3'd1) ? HDR_VER :
        (hdr_idx == 3'd2) ? status_word :
        (hdr_idx == 3'd3) ? hdr_nsamp :
        (hdr_idx == 3'd4) ? hdr_tpos :
        (hdr_idx == 3'd5) ? hdr_ovf :
        (hdr_idx == 3'd6) ? hdr_drop :
                            {16'd0, hdr_post};

    wire fifo_hdr = (state == ST_HDR) && hdr_loaded && !stall;
    wire fifo_pay = pack_valid && !fifo_full;
    assign fifo_wdata = fifo_hdr ? hdr_word : pack_data;
    assign fifo_wr    = fifo_hdr || fifo_pay;

    wire [ADDR_W-1:0] start_addr = wr_ptr - filled[ADDR_W-1:0];
    wire [ADDR_W-1:0] tpos_ent   = trig_addr - start_addr;
    wire [31:0]       tpos_samp  = (tpos_ent * SAMP_PER) + {31'd0, trig_s1_r};

    // ── main FSM ─────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst) begin
            state         <= ST_IDLE;
            wr_ptr        <= {ADDR_W{1'b0}};
            filled        <= {(ADDR_W+1){1'b0}};
            trig_addr     <= {ADDR_W{1'b0}};
            trig_s1_r     <= 1'b0;
            triggered_r   <= 1'b0;
            aborted_r     <= 1'b0;
            overflow_r    <= 32'd0;
            drop_r        <= 32'd0;
            post_got      <= 32'd0;
            hdr_idx       <= 3'd0;
            hdr_loaded    <= 1'b0;
            hdr_nsamp     <= 32'd0;
            hdr_tpos      <= 32'hFFFFFFFF;
            hdr_ovf       <= 32'd0;
            hdr_drop      <= 32'd0;
            hdr_post      <= 16'd0;
            hdr_trig      <= 1'b0;
            hdr_aborted   <= 1'b0;
            hdr_src       <= 2'd0;
            hdr_ch        <= 3'd0;
            hdr_edge      <= 2'd0;
            dump_start    <= {ADDR_W{1'b0}};
            dump_n        <= {(ADDR_W+1){1'b0}};
            rd_issued_cnt <= {(ADDR_W+1){1'b0}};
            pay_expect    <= 32'd0;
            pay_got       <= 32'd0;
            rd_issued     <= 1'b0;
            skid_valid    <= 1'b0;
            skid_data     <= 16'd0;
        end else begin
            rd_issued <= can_rd;

            if (do_start) begin
                wr_ptr        <= {ADDR_W{1'b0}};
                filled        <= {(ADDR_W+1){1'b0}};
                trig_addr     <= {ADDR_W{1'b0}};
                trig_s1_r     <= 1'b0;
                triggered_r   <= 1'b0;
                aborted_r     <= 1'b0;
                overflow_r    <= 32'd0;
                drop_r        <= 32'd0;
                post_got      <= 32'd0;
                hdr_idx       <= 3'd0;
                hdr_loaded    <= 1'b0;
                skid_valid    <= 1'b0;
                rd_issued_cnt <= {(ADDR_W+1){1'b0}};
                pay_got       <= 32'd0;
                state         <= ST_ARM;
            end else begin
                case (state)
                    ST_IDLE: ;

                    ST_ARM: begin
                        if (do_stop) begin
                            aborted_r  <= 1'b1;
                            drop_r     <= drop_r + {16'd0, post_n};
                            hdr_loaded <= 1'b0;
                            hdr_idx    <= 3'd0;
                            state      <= ST_HDR;
                        end else if (wr_fire) begin
                            wr_ptr <= wr_ptr + 1'b1;
                            if (filled != BUF_DEPTH[ADDR_W:0])
                                filled <= filled + 1'b1;
                            if (hit) begin
                                triggered_r <= 1'b1;
                                trig_addr   <= wr_ptr;
                                trig_s1_r   <= hit_s1_w;
                                if ((SAMPLE_MHZ == 200) && !hit_s1_w)
                                    post_got <= 32'd1;
                                else
                                    post_got <= 32'd0;
                                if ((post_n == 16'd0) ||
                                    ((SAMPLE_MHZ == 200) && !hit_s1_w &&
                                     (post_n == 16'd1))) begin
                                    hdr_loaded <= 1'b0;
                                    hdr_idx    <= 3'd0;
                                    state      <= ST_HDR;
                                end else
                                    state <= ST_POST;
                            end
                        end
                    end

                    ST_POST: begin
                        if (do_stop) begin
                            aborted_r <= 1'b1;
                            if (post_got < {16'd0, post_n})
                                drop_r <= drop_r + ({16'd0, post_n} - post_got);
                            hdr_loaded <= 1'b0;
                            hdr_idx    <= 3'd0;
                            state      <= ST_HDR;
                        end else if (would_clobber || post_done) begin
                            if (would_clobber && (post_got < {16'd0, post_n}))
                                drop_r <= drop_r + ({16'd0, post_n} - post_got);
                            hdr_loaded <= 1'b0;
                            hdr_idx    <= 3'd0;
                            state      <= ST_HDR;
                        end else if (wr_fire) begin
                            wr_ptr <= wr_ptr + 1'b1;
                            if (filled != BUF_DEPTH[ADDR_W:0])
                                filled <= filled + 1'b1;
                            else
                                overflow_r <= overflow_r + SAMP_PER[31:0];
                            post_got <= post_got + SAMP_PER[31:0];
                        end
                    end

                    ST_HDR: begin
                        if (!hdr_loaded) begin
                            hdr_loaded    <= 1'b1;
                            hdr_idx       <= 3'd0;
                            hdr_nsamp     <= filled * SAMP_PER[31:0];
                            hdr_tpos      <= triggered_r ? tpos_samp : 32'hFFFFFFFF;
                            hdr_ovf       <= overflow_r;
                            hdr_drop      <= drop_r;
                            hdr_post      <= post_n;
                            hdr_trig      <= triggered_r;
                            hdr_aborted   <= aborted_r;
                            hdr_src       <= src_r;
                            hdr_ch        <= ch_r;
                            hdr_edge      <= edge_r;
                            dump_start    <= start_addr;
                            dump_n        <= filled;
                            rd_issued_cnt <= {(ADDR_W+1){1'b0}};
                            pay_got       <= 32'd0;
                            pay_expect    <= ((filled * SAMP_PER[31:0]) + 32'd3) >> 2;
                            skid_valid    <= 1'b0;
                        end else if (fifo_hdr) begin
                            if (hdr_idx == 3'd7) begin
                                if (filled == 0)
                                    state <= ST_DONE;
                                else
                                    state <= ST_DUMP;
                            end else
                                hdr_idx <= hdr_idx + 1'b1;
                        end
                    end

                    ST_DUMP: begin
                        if (can_rd)
                            rd_issued_cnt <= rd_issued_cnt + 1'b1;

                        if (skid_valid && dump_take)
                            skid_valid <= 1'b0;
                        else if (bram_valid && stall && !skid_valid) begin
                            skid_valid <= 1'b1;
                            skid_data  <= rd_data;
                        end

                        if (fifo_pay)
                            pay_got <= pay_got + 1'b1;

                        if ((pay_got + (fifo_pay ? 32'd1 : 32'd0)) >= pay_expect &&
                            pay_expect != 32'd0 && entries_done)
                            state <= ST_DONE;
                        else if (pay_expect == 32'd0)
                            state <= ST_DONE;
                    end

                    ST_DONE: begin
                        if (do_stop)
                            state <= ST_IDLE;
                    end

                    default: state <= ST_IDLE;
                endcase
            end
        end
    end

    assign armed           = (state == ST_ARM) || (state == ST_POST);
    assign triggered_o     = triggered_r;
    assign cap_done        = (state == ST_DONE);
    assign overflow_cnt    = overflow_r;
    assign drop_cnt        = drop_r;
    assign overflow_sticky = (overflow_r != 32'd0);

endmodule
