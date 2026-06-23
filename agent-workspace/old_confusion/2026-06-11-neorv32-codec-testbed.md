# NeoRV32 Codec Testbed — Status 2026-06-11 21:15

## What Works
- ✅ UART TX/RX at 19200 baud (PRSC=3, BAUD=130, actual ~19231)
- ✅ I2C read at 104 kHz (PRSC=3, CDIV=5)
- ✅ I2C write at 104 kHz
- ✅ CS42448 reads chip ID = 0x04 (correct)
- ✅ CS42448 register reads return correct defaults
- ✅ GPIO5 (CLK_EN) controls clk_wiz_1 reset
- ✅ GPIO2 (RSTCN) controls codec reset
- ✅ Audio clock outputs: MCLK=12.288MHz (Dout_0[0]=V9), SCLK (G22), LRCLK (G21)

## What's Failing
- ❌ CS42448 PWRCTL write returns NACK after power-up sequence
- The codec reads registers fine but won't accept writes to certain registers
- Hypothesis: MCLK must be running AND stable before the codec accepts configuration writes
- The clk_wiz_1 needs PLL lock time after CLK_EN=HIGH

## Key Findings This Session
1. **UART RX bug**: `neorv32_uart0_char_received()` only checks RX_NEMPTY flag — does NOT read data. Must use `neorv32_uart0_char_received_get()` to actually read the byte.
2. **UART baud**: 19200 baud is correct (PRSC=3, BAUD=130 → 19231 Hz, 0.16% error)
3. **I2C speed**: TWI clock formula is `f_SCL = f_main / (4 × prescaler × (1+CDIV))`, NOT the same as UART
4. **I2C read bug**: The address byte in repeated-start phase must use ACK (0), not NACK (1). Only the final data byte uses NACK.
5. **CS42448 register dump** shows alternating 0x03/0x00 pattern — this was the I2C read bug, now fixed
6. **CS42448 PWRCTL write fails** — codec NACKs the data byte when writing 0xFF (power down all)

## GPIO Pin Mapping (from XDC)
| GPIO bit | Pin  | Name   | Function                    |
|----------|------|--------|-----------------------------|
| 0        | E13  | gpio0  | General purpose (not SPI!) |
| 1        | E14  | gpio1  | General purpose             |
| 2        | D14  | RSTCN  | Codec reset (HIGH=active)  |
| 3        | T5   | RSTDN  | Display reset (HIGH=active) |
| 4        | U5   | gpio4  | General purpose             |
| 5        | —    | CLK_EN | clk_wiz_1 reset (HIGH=run)  |

## Audio Clock Outputs (from clk_wiz_1, controlled by GPIO5)
| Signal    | Pin | Frequency    | Notes               |
|-----------|-----|-------------|---------------------|
| Dout_0[0] | V9 | 12.288 MHz | MCLK (master clock) |
| Dout_0[1] | V8 | ?           | SCLK? (shares pin with SPI CS1) |
| Dout_0[2] | U6 | ?           | LRCLK? (shares pin with SPI CS2) |
| SCLK_0    | G22 | ?           | Bit clock           |
| LRCLK_0   | G21 | ?           | Frame clock         |

⚠️ **PIN CONFLICT**: Dout_0[1]=V8 is also SPI CS1 (touch), Dout_0[2]=U6 is also SPI CS2 (SD card). These pins serve dual functions.

## CS42448 Configuration (TDM slave mode, target)
- Address: 0x48
- FUNCMOD (0x03): 0xF4 — slave, auto FM, MFREQ=010
- INTF (0x04): 0x66 — TDM mode for DAC and ADC
- ADCCTL (0x05): 0x1C — single-ended ADC3, HPF
- TXCTL (0x06): 0x63 — soft ramp, zero cross
- PWRCTL (0x02): 0x00 — all powered up

## Next Steps
1. Verify MCLK is actually present on pin V9 when GPIO5=HIGH (oscilloscope)
2. If MCLK isn't running, check clk_wiz_1 lock status
3. Try writing PWRCTL with MCLK confirmed running
4. May need longer delay after CLK_EN before codec accepts writes
5. Consider using Si5351A (0x60) as MCLK source instead of clk_wiz_1