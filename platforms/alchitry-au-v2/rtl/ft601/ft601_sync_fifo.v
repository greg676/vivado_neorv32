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
// 245: OE one clock, then OE+RD. Registered DATA/BE from a cycle with RD
// at the pads are taken on the following clock (rd_armed). WRITE: DATA+BE+WR
// share one IOB load; one word per visit, then IDLE turnaround.
module ft601_sync_fifo (
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

    // Input FFs stay in fabric. Packing them in ILOGIC inserts a 7-series
    // ZHOLD_DELAY (~6.25 ns) that fails setup vs FT601 tCO. Clock insertion
    // delay already covers pad hold. Output pads still use IOB FFs.
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
    assign ft_data = data_oe_r ? data_o_r : 32'bz;
    assign ft_be   = data_oe_r ? be_o_r   : 4'bz;

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
    // Combinational: pop the FWFT FIFO on the same edge DATA/WR are loaded
    // into the output IOB FFs. A registered ready delayed the pop by one
    // cycle and re-drove the previous word.
    assign tx_ready = (state == ST_WRITE) && (txe_r == 1'b0) && !rst;

    wire want_read  = (rxf_r == 1'b0) && rx_ready;
    wire want_write = (txe_r == 1'b0) && tx_valid;

    always @(posedge ft_clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            rd_armed   <= 1'b0;
            oe_n_r     <= 1'b1;
            rd_n_r     <= 1'b1;
            wr_n_r     <= 1'b1;
            data_oe_r  <= 1'b0;
            data_o_r   <= 32'd0;
            be_o_r     <= 4'hF;
            rx_valid_r <= 1'b0;
            rx_data_r  <= 32'd0;
            rx_be_r    <= 4'h0;
        end else begin
            rx_valid_r <= 1'b0;

            case (state)
                ST_IDLE: begin
                    oe_n_r    <= 1'b1;
                    rd_n_r    <= 1'b1;
                    wr_n_r    <= 1'b1;
                    data_oe_r <= 1'b0;
                    rd_armed  <= 1'b0;
                    if (want_read) begin
                        state  <= ST_OE;
                        oe_n_r <= 1'b0;
                    end else if (want_write) begin
                        state     <= ST_WRITE;
                        data_oe_r <= 1'b1;
                        data_o_r  <= tx_data;
                        be_o_r    <= tx_be;
                        wr_n_r    <= 1'b0;
                    end
                end

                ST_OE: begin
                    // OE at pads this cycle. Drop RD so the next edge has
                    // OE+RD at the FT601 (datasheet turnaround).
                    oe_n_r    <= 1'b0;
                    rd_n_r    <= 1'b0;
                    wr_n_r    <= 1'b1;
                    data_oe_r <= 1'b0;
                    rd_armed  <= 1'b0;
                    state     <= ST_READ;
                end

                ST_READ: begin
                    wr_n_r    <= 1'b1;
                    data_oe_r <= 1'b0;
                    // First READ clock: RD is at the pads; pad FFs still hold
                    // the OE-only sample. Arm and wait one clock.
                    if (!rd_armed) begin
                        rd_armed <= 1'b1;
                        oe_n_r   <= 1'b0;
                        rd_n_r   <= 1'b0;
                        state    <= ST_READ;
                    end else if (rxf_r == 1'b0) begin
                        rx_valid_r <= 1'b1;
                        rx_data_r  <= data_i_r;
                        rx_be_r    <= be_i_r;
                        if (rx_ready) begin
                            oe_n_r <= 1'b0;
                            rd_n_r <= 1'b0;
                            state  <= ST_READ;
                        end else begin
                            oe_n_r   <= 1'b1;
                            rd_n_r   <= 1'b1;
                            rd_armed <= 1'b0;
                            state    <= ST_IDLE;
                        end
                    end else begin
                        oe_n_r   <= 1'b1;
                        rd_n_r   <= 1'b1;
                        rd_armed <= 1'b0;
                        state    <= ST_IDLE;
                    end
                end

                ST_WRITE: begin
                    wr_n_r    <= 1'b1;
                    data_oe_r <= 1'b0;
                    oe_n_r    <= 1'b1;
                    rd_n_r    <= 1'b1;
                    state     <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
