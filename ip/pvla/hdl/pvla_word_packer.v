`timescale 1ns / 1ps
// Visible 32-bit USB packer: N samples fill one little-endian word.
//
//   4 ch  -> 8 samples/word   [3:0]=t+0  ... [31:28]=t+7
//   8 ch  -> 4 samples/word   [7:0]=t+0  ... [31:24]=t+3
//  16 ch  -> 2 samples/word   [15:0]=t+0 ... [31:16]=t+1
//
// BE at the PHY is 4'hF. Every DATA bit is a packed sample bit
// (4 ch uses [31:28] as sample t+7, not "unused").
// Each mode is its own generate so the schematic shows the mux/shift.
module pvla_word_packer #(
    parameter integer C_NUM_CH = 8
) (
    input  wire                clk,
    input  wire                rst,
    input  wire                arm,
    input  wire [C_NUM_CH-1:0] sample_i,
    input  wire                sample_valid,
    output wire                sample_ready,
    (* keep = "true" *) output reg [31:0] word_o,
    output reg                 word_valid,
    input  wire                word_ready
);

    wire stall = word_valid && !word_ready;
    assign sample_ready = arm && !stall && !rst;

    generate
        if (C_NUM_CH == 4) begin : g_pack4
            // 8 nibbles / USB word. acc is t+0..t+6; t+7 is word_o[31:28].
            reg [27:0] acc;
            reg [2:0]  fill;
            always @(posedge clk) begin
                if (rst || !arm) begin
                    acc        <= 28'h0;
                    fill       <= 3'd0;
                    word_o     <= 32'h0;
                    word_valid <= 1'b0;
                end else begin
                    if (word_valid && word_ready)
                        word_valid <= 1'b0;
                    if (sample_valid && sample_ready) begin
                        case (fill)
                            3'd0: begin acc[3:0]   <= sample_i; fill <= 3'd1; end
                            3'd1: begin acc[7:4]   <= sample_i; fill <= 3'd2; end
                            3'd2: begin acc[11:8]  <= sample_i; fill <= 3'd3; end
                            3'd3: begin acc[15:12] <= sample_i; fill <= 3'd4; end
                            3'd4: begin acc[19:16] <= sample_i; fill <= 3'd5; end
                            3'd5: begin acc[23:20] <= sample_i; fill <= 3'd6; end
                            3'd6: begin acc[27:24] <= sample_i; fill <= 3'd7; end
                            default: begin
                                word_o[27:0]  <= acc;
                                word_o[31:28] <= sample_i;  // t+7 fills DATA[31:28]
                                word_valid    <= 1'b1;
                                acc           <= 28'h0;
                                fill          <= 3'd0;
                            end
                        endcase
                    end
                end
            end
        end else if (C_NUM_CH == 16) begin : g_pack16
            // 2 halfwords / USB word
            reg        fill;
            reg [15:0] acc;
            always @(posedge clk) begin
                if (rst || !arm) begin
                    acc        <= 16'h0;
                    fill       <= 1'b0;
                    word_o     <= 32'h0;
                    word_valid <= 1'b0;
                end else begin
                    if (word_valid && word_ready)
                        word_valid <= 1'b0;
                    if (sample_valid && sample_ready) begin
                        if (!fill) begin
                            acc  <= sample_i;
                            fill <= 1'b1;
                        end else begin
                            word_o[15:0]  <= acc;
                            word_o[31:16] <= sample_i;  // t+1 fills DATA[31:16]
                            word_valid    <= 1'b1;
                            acc           <= 16'h0;
                            fill          <= 1'b0;
                        end
                    end
                end
            end
        end else begin : g_pack8
            // 4 bytes / USB word (default 8 ch). acc is t+0..t+2; t+3 is word_o[31:24].
            reg [23:0] acc;
            reg [1:0]  fill;
            always @(posedge clk) begin
                if (rst || !arm) begin
                    acc        <= 24'h0;
                    fill       <= 2'd0;
                    word_o     <= 32'h0;
                    word_valid <= 1'b0;
                end else begin
                    if (word_valid && word_ready)
                        word_valid <= 1'b0;
                    if (sample_valid && sample_ready) begin
                        case (fill)
                            2'd0: begin acc[7:0]   <= sample_i; fill <= 2'd1; end
                            2'd1: begin acc[15:8]  <= sample_i; fill <= 2'd2; end
                            2'd2: begin acc[23:16] <= sample_i; fill <= 2'd3; end
                            default: begin
                                word_o[23:0]  <= acc;
                                word_o[31:24] <= sample_i;  // t+3 fills DATA[31:24]
                                word_valid    <= 1'b1;
                                acc           <= 24'h0;
                                fill          <= 2'd0;
                            end
                        endcase
                    end
                end
            end
        end
    endgenerate

endmodule
