`timescale 1ns / 1ps
// Inspect FT601 245 pad timing. Counts protocol violations; does not drive.
module ft601_245_monitor (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] ft_data,
    input  wire [3:0]  ft_be,
    input  wire        ft_rxf,
    input  wire        ft_txe,
    input  wire        ft_oe,
    input  wire        ft_rd,
    input  wire        ft_wr,
    input  wire        fpga_driving,
    output integer     violations
);

    integer v;
    assign violations = v;

    reg oe_d, rd_d, wr_d, drive_d;

    always @(posedge clk) begin
        if (rst) begin
            v       <= 0;
            oe_d    <= 1'b1;
            rd_d    <= 1'b1;
            wr_d    <= 1'b1;
            drive_d <= 1'b0;
        end else begin
            oe_d    <= ft_oe;
            rd_d    <= ft_rd;
            wr_d    <= ft_wr;
            drive_d <= fpga_driving;

            if (ft_oe == 1'b0 && ft_wr == 1'b0) begin
                $display("TIME %0t: OE# and WR# both low", $time);
                v <= v + 1;
            end
            if (ft_rd == 1'b0 && ft_oe == 1'b1) begin
                $display("TIME %0t: RD# low while OE# high", $time);
                v <= v + 1;
            end
            if (ft_wr == 1'b0 && ft_rd == 1'b0) begin
                $display("TIME %0t: RD# and WR# both low", $time);
                v <= v + 1;
            end
            if (ft_oe == 1'b0 && fpga_driving) begin
                $display("TIME %0t: FPGA driving DATA while OE# low", $time);
                v <= v + 1;
            end
            if (ft_wr == 1'b0 && !fpga_driving) begin
                $display("TIME %0t: WR# low but FPGA not driving DATA", $time);
                v <= v + 1;
            end
            // Datasheet turnaround: OE# falls at least one clock before RD#.
            if (oe_d == 1'b1 && ft_oe == 1'b0 && ft_rd == 1'b0) begin
                $display("TIME %0t: OE# and RD# fell on the same clock", $time);
                v <= v + 1;
            end
            if (ft_wr == 1'b0 && wr_d == 1'b0) begin
                $display("TIME %0t: WR# held more than one clock (DUT writes 1 word/visit)", $time);
                v <= v + 1;
            end
            if (ft_wr == 1'b0 && ft_be === 4'bzzzz) begin
                $display("TIME %0t: BE high-Z during WR#", $time);
                v <= v + 1;
            end
            if (drive_d && ft_oe == 1'b0) begin
                $display("TIME %0t: FPGA still driving into OE# cycle", $time);
                v <= v + 1;
            end
        end
    end

endmodule
