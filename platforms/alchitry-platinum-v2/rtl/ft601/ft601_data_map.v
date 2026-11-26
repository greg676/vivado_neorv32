`timescale 1ns / 1ps
// Named FT601 DATA bit map. PINOUT selects the *documented* Alchitry
// package (XDC), not a bit shuffle: Alchitry ft_data[n] = FT601Q DATA[n]
// = USB little-endian bit n of the 32-bit word (byte 0 = DATA[7:0]).
//
// PT_ALPHA vs production V2 differs only in PACKAGE_PIN for DATA[0:13]
// (first-batch Bank B). Do not bit-reverse or nibble-swap here.
module ft601_data_map #(
    parameter PINOUT = "PT_ALPHA"
) (
    input  wire [31:0] d_in,
    output wire [31:0] d_out
);

    generate
        if (PINOUT == "PT_ALPHA" || PINOUT == "V2") begin : g_identity
            assign d_out = d_in;
        end else begin : g_bad
            initial begin
                $display("ft601_data_map: unknown PINOUT %0s", PINOUT);
                $finish;
            end
            assign d_out = 32'hxxxxxxxx;
        end
    endgenerate

endmodule
