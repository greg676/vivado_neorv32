`timescale 1ns / 1ps
// Minimal FT601 245-FIFO behavioural model for loopback simulation.
module ft601_bus_model #(
    parameter DEPTH = 256
) (
    input  wire        clk,
    input  wire        rst,

    inout  wire [31:0] ft_data,
    inout  wire [3:0]  ft_be,
    output wire        ft_rxf,
    output wire        ft_txe,
    input  wire        ft_oe,
    input  wire        ft_rd,
    input  wire        ft_wr,

    input  wire        host_push_en,
    input  wire [31:0] host_push_data,
    input  wire [3:0]  host_push_be,
    output wire        host_push_full,

    input  wire        host_pop_en,
    output wire [31:0] host_pop_data,
    output wire [3:0]  host_pop_be,
    output wire        host_pop_empty
);

    reg [35:0] to_fpga   [0:DEPTH-1];
    reg [35:0] from_fpga [0:DEPTH-1];
    integer    to_wr, to_rd, to_count;
    integer    from_wr, from_rd, from_count;

    assign host_push_full = (to_count >= DEPTH);
    assign host_pop_empty = (from_count == 0);
    assign host_pop_data  = from_fpga[from_rd][31:0];
    assign host_pop_be    = from_fpga[from_rd][35:32];

    wire [35:0] rd_word = to_fpga[to_rd];
    wire        driving = (ft_oe == 1'b0) && (to_count != 0);

    assign ft_data = driving ? rd_word[31:0]  : 32'bz;
    assign ft_be   = driving ? rd_word[35:32] : 4'bz;
    assign ft_rxf  = (to_count == 0);
    assign ft_txe  = (from_count >= DEPTH);

    wire fpga_read  = (ft_oe == 1'b0) && (ft_rd == 1'b0) && (to_count != 0);
    wire fpga_write = (ft_wr == 1'b0) && (from_count < DEPTH);
    wire host_push  = host_push_en && (to_count < DEPTH);
    wire host_pop   = host_pop_en && (from_count != 0);

    always @(posedge clk) begin
        if (rst) begin
            to_wr      <= 0;
            to_rd      <= 0;
            to_count   <= 0;
            from_wr    <= 0;
            from_rd    <= 0;
            from_count <= 0;
        end else begin
            if (host_push) begin
                to_fpga[to_wr] <= {host_push_be, host_push_data};
                to_wr          <= (to_wr + 1) % DEPTH;
            end
            if (fpga_read)
                to_rd <= (to_rd + 1) % DEPTH;

            if (host_push && fpga_read)
                to_count <= to_count;
            else if (host_push)
                to_count <= to_count + 1;
            else if (fpga_read)
                to_count <= to_count - 1;

            if (fpga_write) begin
                from_fpga[from_wr] <= {ft_be, ft_data};
                from_wr            <= (from_wr + 1) % DEPTH;
            end
            if (host_pop)
                from_rd <= (from_rd + 1) % DEPTH;

            if (fpga_write && host_pop)
                from_count <= from_count;
            else if (fpga_write)
                from_count <= from_count + 1;
            else if (host_pop)
                from_count <= from_count - 1;
        end
    end

endmodule
