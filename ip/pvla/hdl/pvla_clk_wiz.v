`timescale 1ns / 1ps
// Clocking Wizard equivalent (MMCME2_BASE). Not a nested clk_wiz .xci.
//
//   CLKIN   = ft_clk 100 MHz
//   CLKOUT0 = 100 MHz  -> 16 ch packer (2 samples / USB word)
//   CLKOUT1 = 200 MHz  ->  8 ch packer (4 samples / USB word)
//   CLKOUT2 = 400 MHz  ->  4 ch packer (8 samples / USB word)
//
// VCO = 800 MHz (MULT=8, DIVCLK=1). Artix-7 -1 safe. Matches advertised
// 400/200/100 MS/s = 50 Mword/s USB. Do not advertise 800/400/200.
module pvla_clk_wiz (
    input  wire clk_in,
    input  wire rst,
    output wire clk100,
    output wire clk200,
    output wire clk400,
    output wire locked
);

    wire clkfb_unbuf;
    wire clkfb;
    wire clk100_unbuf;
    wire clk200_unbuf;
    wire clk400_unbuf;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (8.000),
        .CLKFBOUT_PHASE     (0.000),
        .CLKIN1_PERIOD      (10.000),
        .CLKOUT0_DIVIDE_F   (8.000),
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT0_PHASE      (0.000),
        .CLKOUT1_DIVIDE     (4),
        .CLKOUT1_DUTY_CYCLE (0.500),
        .CLKOUT1_PHASE      (0.000),
        .CLKOUT2_DIVIDE     (2),
        .CLKOUT2_DUTY_CYCLE (0.500),
        .CLKOUT2_PHASE      (0.000),
        .CLKOUT3_DIVIDE     (1),
        .CLKOUT4_DIVIDE     (1),
        .CLKOUT5_DIVIDE     (1),
        .CLKOUT6_DIVIDE     (1),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKOUT0   (clk100_unbuf),
        .CLKOUT0B  (),
        .CLKOUT1   (clk200_unbuf),
        .CLKOUT1B  (),
        .CLKOUT2   (clk400_unbuf),
        .CLKOUT2B  (),
        .CLKOUT3   (),
        .CLKOUT3B  (),
        .CLKOUT4   (),
        .CLKOUT5   (),
        .CLKOUT6   (),
        .CLKFBOUT  (clkfb_unbuf),
        .LOCKED    (locked),
        .CLKIN1    (clk_in),
        .PWRDWN    (1'b0),
        .RST       (rst),
        .CLKFBIN   (clkfb)
    );

    BUFG u_fb  (.I(clkfb_unbuf),  .O(clkfb));
    BUFG u_100 (.I(clk100_unbuf), .O(clk100));
    BUFG u_200 (.I(clk200_unbuf), .O(clk200));
    BUFG u_400 (.I(clk400_unbuf), .O(clk400));

endmodule
