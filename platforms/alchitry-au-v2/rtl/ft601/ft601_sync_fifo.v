`timescale 1ns / 1ps
// FT601 245 synchronous FIFO master (32-bit).
// Active-low FT601 strobes keep Alchitry port names: ft_rxf, ft_txe, ft_oe,
// ft_rd, ft_wr.
//
// Pads are registered (DATA/BE/RXF/TXE in fabric FFs; OE/RD/WR/DATA/BE out
// in IOB). The FSM never looks at a live pad.
//
// Byte enables (FTDI 32-bit 245, little-endian USB):
//   BE[0] valid -> DATA[7:0]   = USB byte 0 of the 32-bit word
//   BE[1] valid -> DATA[15:8]  = USB byte 1
//   BE[2] valid -> DATA[23:16] = USB byte 2
//   BE[3] valid -> DATA[31:24] = USB byte 3
// 1 = that byte is part of the transfer; 0 = unused. Host bulk tools in
// this repo always send/expect 4-byte words (BE=0xF on TX).
//
// Labs-V2 ft.luc compiles to combinational always @* plus a state dff:
//   DATA/BE = TX FIFO dout whenever not reading (IDLE and WRITE)
//   ft_wr   = write_fifo.empty only while state.q == WRITE (else 1)
// IOB FFs then sample that combo. WR therefore falls one ft_clk after
// DATA is already on the bus — no extra SETUP state. WRITE bursts until
// TXE or empty, like ft.luc.
// ALWAYS_DRIVE: TX-only never RD, so never Z (OBUF). OBUFT T-to-O was WNS.
//
// DS_FT600Q / AN_386 / AN_412: 245 one-channel FIFO is 4 KiB * 2 ping-pong.
// Write the 4 KiB as one transaction (1024 x 32-bit, BE=0xF), then raise WR
// and wait TXE. TN_191 Fig.12: a word with TXE_N=1 is not received. ubfx /
// CoLA / FPGA-ftdi245fifo: fixed-size bursts so TXE cannot change mid-block.
module ft601_sync_fifo #(
    parameter ALWAYS_DRIVE = 0,
    parameter TX_BURST_WORDS = 1024
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

    output wire [31:0] rx_data,
    output wire [3:0]  rx_be,
    output wire        rx_valid,
    input  wire        rx_ready,

    input  wire [31:0] tx_data,
    input  wire [3:0]  tx_be,
    input  wire        tx_valid,
    output wire        tx_ready
);

    localparam ST_IDLE  = 2'd0;
    localparam ST_OE    = 2'd1;
    localparam ST_READ  = 2'd2;
    localparam ST_WRITE = 2'd3;

    (* IOB = "FALSE" *) reg        rxf_r;
    (* IOB = "FALSE" *) reg        txe_r;
    (* IOB = "FALSE" *) reg [31:0] data_i_r;
    (* IOB = "FALSE" *) reg [3:0]  be_i_r;

    (* IOB = "TRUE" *) reg        oe_n_r;
    (* IOB = "TRUE" *) reg        rd_n_r;
    (* IOB = "TRUE" *) reg        wr_n_r;
    (* IOB = "TRUE" *) reg        data_oe_r;
    (* IOB = "TRUE" *) reg [31:0] data_o_r;
    (* IOB = "TRUE" *) reg [3:0]  be_o_r;

    assign ft_oe = oe_n_r;
    assign ft_rd = rd_n_r;
    assign ft_wr = wr_n_r;
    generate
        if (ALWAYS_DRIVE) begin : g_drive
            assign ft_data = data_o_r;
            assign ft_be   = be_o_r;
        end else begin : g_z
            assign ft_data = data_oe_r ? data_o_r : 32'bz;
            assign ft_be   = data_oe_r ? be_o_r   : 4'bz;
        end
    endgenerate

    always @(posedge ft_clk) begin
        rxf_r    <= ft_rxf;
        txe_r    <= ft_txe;
        data_i_r <= ft_data;
        be_i_r   <= ft_be;
    end

    reg [1:0]  state;
    reg        rd_armed;
    reg        rx_valid_r;
    reg [31:0] rx_data_r;
    reg [3:0]  rx_be_r;

    assign rx_valid = rx_valid_r;
    assign rx_data  = rx_data_r;
    assign rx_be    = rx_be_r;

    wire reading = (state == ST_OE) || (state == ST_READ);
    wire writing = (state == ST_WRITE);

    reg [10:0] burst_w;
    wire burst_room = (burst_w < TX_BURST_WORDS[10:0]);

    // End the 4 KiB transaction by count (not TXE). Live TXE still gates WR
    // if the ping-pong buffer is not ready. IOB WR; combo WR is WNS −6.5 ns.
    wire can_wr    = writing && tx_valid && burst_room && (ft_txe == 1'b0) && !rst;
    wire wr_n_c    = can_wr ? 1'b0 : 1'b1;
    wire reading_z = reading && !ALWAYS_DRIVE;
    wire data_oe_c = ~reading_z;
    wire oe_n_c    = (state == ST_OE)   ? 1'b0 :
                     (state == ST_READ) ? ~rx_ready : 1'b1;
    wire rd_n_c    = (state == ST_READ) ? ~rx_ready : 1'b1;

    assign tx_ready = can_wr;

    wire want_read  = (rxf_r == 1'b0) && rx_ready;
    wire want_write = (txe_r == 1'b0) && tx_valid;

    always @(posedge ft_clk) begin
        if (rst) begin
            oe_n_r    <= 1'b1;
            rd_n_r    <= 1'b1;
            wr_n_r    <= 1'b1;
            data_oe_r <= ALWAYS_DRIVE ? 1'b1 : 1'b0;
            data_o_r  <= 32'd0;
            be_o_r    <= 4'hF;
        end else begin
            oe_n_r    <= oe_n_c;
            rd_n_r    <= rd_n_c;
            wr_n_r    <= wr_n_c;
            data_oe_r <= data_oe_c;
            data_o_r  <= tx_data;
            be_o_r    <= tx_be;
        end
    end

    always @(posedge ft_clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            rd_armed   <= 1'b0;
            burst_w    <= 11'd0;
            rx_valid_r <= 1'b0;
            rx_data_r  <= 32'd0;
            rx_be_r    <= 4'h0;
        end else begin
            rx_valid_r <= 1'b0;
            if (!writing)
                burst_w <= 11'd0;
            else if (can_wr)
                burst_w <= burst_w + 1'b1;

            case (state)
                ST_IDLE: begin
                    rd_armed <= 1'b0;
                    if (want_read)
                        state <= ST_OE;
                    else if (want_write)
                        state <= ST_WRITE;
                end

                ST_OE: begin
                    rd_armed <= 1'b0;
                    state    <= ST_READ;
                end

                ST_READ: begin
                    if (!rd_armed) begin
                        rd_armed <= 1'b1;
                        state    <= ST_READ;
                    end else if (rxf_r == 1'b0) begin
                        rx_valid_r <= 1'b1;
                        rx_data_r  <= data_i_r;
                        rx_be_r    <= be_i_r;
                        if (rx_ready)
                            state <= ST_READ;
                        else begin
                            rd_armed <= 1'b0;
                            state    <= ST_IDLE;
                        end
                    end else begin
                        rd_armed <= 1'b0;
                        state    <= ST_IDLE;
                    end
                end

                ST_WRITE: begin
                    if (txe_r || !tx_valid || !burst_room)
                        state <= ST_IDLE;
                    else
                        state <= ST_WRITE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
