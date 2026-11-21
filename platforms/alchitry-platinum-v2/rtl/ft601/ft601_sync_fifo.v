`timescale 1ns / 1ps
// FT601 245 synchronous FIFO master (32-bit).
// Active-low FT601 strobes keep Alchitry port names: ft_rxf, ft_txe, ft_oe,
// ft_rd, ft_wr.
//
// Read:  OE one cycle, then OE+RD. Capture DATA/BE while ft_rxf is low.
// Write: DATA/BE/WR registered together; accepted on the next rising ft_clk
//        while ft_txe is low. One word per WRITE visit (correct, simple).
// Turnaround always passes through IDLE so FPGA drive and OE never overlap.
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

    (* IOB = "TRUE" *) reg rxf_r;
    (* IOB = "TRUE" *) reg txe_r;

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
        rxf_r <= ft_rxf;
        txe_r <= ft_txe;
    end

    reg [1:0]  state;
    reg        rx_valid_r;
    reg [31:0] rx_data_r;
    reg [3:0]  rx_be_r;

    assign rx_valid = rx_valid_r;
    assign rx_data  = rx_data_r;
    assign rx_be    = rx_be_r;
    // Combinational: pop the FWFT FIFO on the same edge the FT601 samples
    // DATA/WR. A registered ready delayed the pop by one cycle and
    // re-drove the previous word.
    assign tx_ready = (state == ST_WRITE) && (ft_txe == 1'b0) && !rst;

    wire want_read  = (rxf_r == 1'b0) && rx_ready;
    wire want_write = (txe_r == 1'b0) && tx_valid;

    always @(posedge ft_clk) begin
        if (rst) begin
            state      <= ST_IDLE;
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
                    oe_n_r <= 1'b0;
                    rd_n_r <= 1'b0;
                    state  <= ST_READ;
                end

                ST_READ: begin
                    // Pads have OE=0, RD=0 this edge. Sample live RXF so we
                    // do not capture a cycle after the FIFO goes empty.
                    if (ft_rxf == 1'b0) begin
                        if (rx_ready) begin
                            rx_valid_r <= 1'b1;
                            rx_data_r  <= ft_data;
                            rx_be_r    <= ft_be;
                            oe_n_r     <= 1'b0;
                            rd_n_r     <= 1'b0;
                        end else begin
                            oe_n_r <= 1'b1;
                            rd_n_r <= 1'b1;
                            state  <= ST_IDLE;
                        end
                    end else begin
                        oe_n_r <= 1'b1;
                        rd_n_r <= 1'b1;
                        state  <= ST_IDLE;
                    end
                end

                ST_WRITE: begin
                    // Pads have WR=0 and DATA this edge. Live TXE decides
                    // whether the FT601 accepted the word.
                    wr_n_r    <= 1'b1;
                    data_oe_r <= 1'b0;
                    state     <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
