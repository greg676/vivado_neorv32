`timescale 1ns / 1ps
// FT601 datapath.
// MODE = "LOOPBACK" : host words -> FIFO -> host
// MODE = "TX_ONLY"  : never RD; WR incrementing 32-bit words while TXE
// MODE = "RX_ONLY"  : RD while RXF; latch first word and TX that constant
module ft601_loopback_core #(
    parameter MODE = "LOOPBACK"
) (
    input  wire        ft_clk,
    input  wire        rst,

    inout  wire [31:0] ft_data,
    inout  wire [3:0]  ft_be,
    input  wire        ft_rxf,
    input  wire        ft_txe,
    output wire        ft_oe,
    output wire        ft_rd,
    output wire        ft_wr,

    output wire        overflow_sticky,
    output wire        fifo_empty,
    output wire        fifo_full,
    output wire        rx_active,
    output wire        tx_active,
    output wire [31:0] first_rx_word,
    output wire        first_rx_valid
);

    wire [31:0] rx_data;
    wire [3:0]  rx_be;
    wire        rx_valid;
    wire        rx_ready;

    wire [31:0] tx_data;
    wire [3:0]  tx_be;
    wire        tx_valid;
    wire        tx_ready;

    wire        fifo_full_w;
    wire        fifo_almost_full;
    wire        fifo_empty_w;
    wire [31:0] fifo_rdata;
    wire [9:0]  fifo_count;

    assign fifo_empty = fifo_empty_w;
    assign fifo_full  = fifo_full_w;
    assign rx_active  = rx_valid;
    assign tx_active  = tx_ready;

    generate
        if (MODE == "TX_ONLY") begin : g_tx_only
            // Isolation: FPGA never asserts RD. Host must IN only.
            assign rx_ready         = 1'b0;
            assign fifo_full_w      = 1'b0;
            assign fifo_almost_full = 1'b0;
            assign fifo_empty_w     = 1'b1;
            assign fifo_rdata       = 32'd0;
            assign fifo_count       = 10'd0;
            assign first_rx_word    = 32'd0;
            assign first_rx_valid   = 1'b0;

            reg [31:0] counter;
            always @(posedge ft_clk) begin
                if (rst)
                    counter <= 32'd0;
                else if (tx_ready)
                    counter <= counter + 1'b1;
            end

            assign tx_data  = counter;
            assign tx_be    = 4'hF;
            assign tx_valid = 1'b1;
        end else if (MODE == "RX_ONLY") begin : g_rx_only
            // Drain host OUT. Report the first captured word by TXing that
            // constant (not a full echo). Labeled on the host as first-RX.
            assign rx_ready         = 1'b1;
            assign fifo_full_w      = 1'b0;
            assign fifo_almost_full = 1'b0;
            assign fifo_empty_w     = 1'b1;
            assign fifo_rdata       = 32'd0;
            assign fifo_count       = 10'd0;

            reg        got_first;
            reg [31:0] first_word;
            always @(posedge ft_clk) begin
                if (rst) begin
                    got_first  <= 1'b0;
                    first_word <= 32'd0;
                end else if (rx_valid && !got_first) begin
                    got_first  <= 1'b1;
                    first_word <= rx_data;
                end
            end

            assign first_rx_word  = first_word;
            assign first_rx_valid = got_first;
            assign tx_data        = first_word;
            assign tx_be          = 4'hF;
            assign tx_valid       = got_first;
        end else begin : g_loopback
            assign first_rx_word  = 32'd0;
            assign first_rx_valid = 1'b0;
            assign rx_ready = !fifo_almost_full;

            // 32-bit echo only. Do not replay captured BE: a sampled 0/Z on
            // BE[i] would drop USB byte i (DATA[8*i+7:8*i]) and shift the
            // host stream. Host tools always use 4-byte words.
            ft601_fwft_fifo #(
                .WIDTH (32),
                .DEPTH (512),
                .ADDR_W(9)
            ) u_fifo (
                .clk         (ft_clk),
                .rst         (rst),
                .wr_data     (rx_data),
                .wr_en       (rx_valid),
                .full        (fifo_full_w),
                .almost_full (fifo_almost_full),
                .rd_data     (fifo_rdata),
                .rd_en       (tx_ready),
                .empty       (fifo_empty_w),
                .count       (fifo_count)
            );

            assign tx_data  = fifo_rdata;
            assign tx_be    = 4'hF;
            assign tx_valid = !fifo_empty_w;
        end
    endgenerate

    ft601_sync_fifo u_phy (
        .ft_clk   (ft_clk),
        .rst      (rst),
        .ft_data  (ft_data),
        .ft_be    (ft_be),
        .ft_rxf   (ft_rxf),
        .ft_txe   (ft_txe),
        .ft_oe    (ft_oe),
        .ft_rd    (ft_rd),
        .ft_wr    (ft_wr),
        .rx_data  (rx_data),
        .rx_be    (rx_be),
        .rx_valid (rx_valid),
        .rx_ready (rx_ready),
        .tx_data  (tx_data),
        .tx_be    (tx_be),
        .tx_valid (tx_valid),
        .tx_ready (tx_ready)
    );

    reg ovf;
    always @(posedge ft_clk) begin
        if (rst)
            ovf <= 1'b0;
        else if (rx_valid && !rx_ready)
            ovf <= 1'b1;
    end
    assign overflow_sticky = ovf;

endmodule
