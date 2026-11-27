`timescale 1ns / 1ps
// Internal fabric source: counter, walking-one, or BD-routed probe_i.
// C_INPUT_PATH in the parent picks this block vs external pins — not mixed.
module pvla_internal_src #(
    parameter integer C_NUM_CH = 8
) (
    input  wire                clk,
    input  wire                rst,
    input  wire                ce,
    input  wire [1:0]          src,       // 0 counter  1 walking-one  2 BD probe
    input  wire [C_NUM_CH-1:0] probe_i,
    output reg  [C_NUM_CH-1:0] sample_o,
    output reg                 sample_valid
);

    localparam [1:0] SRC_CTR  = 2'd0;
    localparam [1:0] SRC_WALK = 2'd1;

    reg [31:0] n;

    always @(posedge clk) begin
        if (rst) begin
            n            <= 32'd0;
            sample_o     <= {C_NUM_CH{1'b0}};
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;
            if (ce) begin
                sample_valid <= 1'b1;
                n            <= n + 32'd1;
                case (src)
                    SRC_WALK: sample_o <= {{(C_NUM_CH-1){1'b0}}, 1'b1}
                                          << n[($clog2(C_NUM_CH)-1):0];
                    SRC_CTR:  sample_o <= n[C_NUM_CH-1:0];
                    default:  sample_o <= probe_i;
                endcase
            end
        end
    end

endmodule
