# Alchitry PTV2 Pin Mapping — Complete

## Source Files
- **`.acf`**: `/home/greg-jack/Desktop/ft_plus_v2.acf` (Br connector names)
- **`.xdc`**: `/home/greg-jack/Desktop/alchitry.xdc` (FPGA package pins — GROUND TRUTH)

## Alchitry Pt V2 Fixed-Function Pins

| Signal | FPGA Pin | Notes |
|---|---|---|
| **clk** (onboard 100MHz) | **W19** | Pt V2 system clock |
| **rst_n** (reset button) | **N15** | Active-low reset button |
| **usb_rx** (USB-UART) | **AA20** | FTDI UART bridge RX |
| **usb_tx** (USB-UART) | **AA21** | FTDI UART bridge TX |
| **led[0]** | P19 | |
| **led[1]** | P20 | |
| **led[2]** | T21 | |
| **led[3]** | R19 | |
| **led[4]** | V22 | |
| **led[5]** | U21 | |
| **led[6]** | T20 | |
| **led[7]** | W20 | |

## FT601 (Ft+ Addon, PT_ALPHA connector TOP)

| FT601 Signal | FPGA Pin | Signal | FPGA Pin |
|---|---|---|---|
| ft_data[0] | AB13 | ft_data[16] | G4 |
| ft_data[1] | AA13 | ft_data[17] | H3 |
| ft_data[2] | AA11 | ft_data[18] | G3 |
| ft_data[3] | AA10 | ft_data[19] | P5 |
| ft_data[4] | AB12 | ft_data[20] | P4 |
| ft_data[5] | AB11 | ft_data[21] | P6 |
| ft_data[6] | Y14 | ft_data[22] | N5 |
| ft_data[7] | W14 | ft_data[23] | M6 |
| ft_data[8] | AB15 | ft_data[24] | M5 |
| ft_data[9] | AA15 | ft_data[25] | L5 |
| ft_data[10] | W16 | ft_data[26] | L4 |
| ft_data[11] | W15 | ft_data[27] | K6 |
| ft_data[12] | AB17 | ft_data[28] | J6 |
| ft_data[13] | AB16 | ft_data[29] | E2 |
| ft_data[14] | V19 | ft_data[30] | D2 |
| ft_data[15] | V18 | ft_data[31] | M3 |
| **ft_clk** | **H4** | ft_be[0] | M2 |
| ft_wakeup | AB22 | ft_be[1] | M1 |
| ft_reset | AB21 | ft_be[2] | L1 |
| ft_rxf | N2 | ft_be[3] | F3 |
| ft_txe | P2 | ft_oe | AB18 |
| ft_rd | AA18 | ft_wr | E3 |

## Audio & Debug (Br Breakout V2, BOTTOM)

| Signal | FPGA Pin | Notes |
|---|---|---|
| **tck** (JTAG) | **AA3** | J-Link JTAG clock |
| **tdi** (JTAG) | **AB1** | J-Link JTAG data in |
| **tdo** (JTAG) | **AA1** | J-Link JTAG data out |
| **tms** (JTAG) | **Y3** | J-Link JTAG mode select |
| **gpio[0]** | **A15** | GPIO |
| **gpio[1]** | **A16** | GPIO |
| **gpio[2]** | **E16** | GPIO |
| **mclk** | **D16** | Audio master clock (24.576MHz to codec) |
| **sclk** | **A19** | I2S/TDM bit clock |
| **lrclk** | **A18** | I2S/TDM word clock (FSYNC) |
| **scl** | **B21** | I2C clock |
| **sda** | **E21** | I2C data |
| **din** | **A21** | I2S/TDM data IN (from codec ADC) |
| **dout** | **D21** | I2S/TDM data OUT (to codec DAC) |

## What We Need to Port

### From Current XDC (nogpio.xdc) → New Pins

| Signal | Old XDC Pin | New Correct Pin |
|---|---|---|
| clk (100MHz) | N15 | **W19** |
| reset | W19 | **N15** |
| JTAG TCK | AB22 | **AA3** |
| JTAG TDI | E3 | **AB1** |
| JTAG TDO | M2 | **AA1** |
| JTAG TMS | J6 | **Y3** |
| UART RXD | M3 | **AA20** (usb_rx) |
| UART TXD | K6 | **AA21** (usb_tx) |
| TWI SCL | AB21 | **B21** |
| TWI SDA | F3 | **E21** |
| GPIO[0] | AA20 | **A15** |
| GPIO[1] | AA19 | **A16** |
| GPIO[2] | AA18 | **E16** |

### New Signals to Add to Block Design

| Signal | FPGA Pin | Direction | Purpose |
|---|---|---|---|
| mclk | D16 | output | 24.576MHz audio master clock |
| sclk | A19 | output | I2S/TDM bit clock |
| lrclk | A18 | output | I2S/TDM word/frame clock |
| din | A21 | input | Audio data from codec (ADC → FPGA) |
| dout | D21 | output | Audio data to codec (FPGA → DAC) |
| led[7:0] | P19,P20,T21,R19,V22,U21,T20,W20 | output | Debug LEDs |

### FT601 (Future — NOT in current design)

FT601 requires 42 signals (data[31:0], be[3:0], clk, rxf, txe, oe, rd, wr, reset, wakeup) all mapped above. This will be a separate IP block added to the block design later.
