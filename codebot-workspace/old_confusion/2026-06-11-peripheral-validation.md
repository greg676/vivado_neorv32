# 2026-06-11 — Peripheral Validation: Debug Console v2 + RP2040 Passthrough

## Bitstream On FPGA
- **File:** `neorv_basic_top.bit` (built 09:15 PDT, 2026-06-11)
- **Block design:** `neorv_basic` — NeoRV32 + clk_wiz_0 (160MHz) + clk_wiz_1 (12.288MHz) + clk_gen_0 + ilslices
- **Top-level:** `neorv_basic_top.v`

## GPIO Mapping (NeoRV32 gpio_o)
| Bit | Name | Function |
|-----|------|----------|
| 0 | A0 | Codec address bit 0 |
| 1 | A1 | Codec address bit 1 |
| 2 | RSTCN | Codec reset (active-low) |
| 3 | RSTDN | Display reset (active-low) |
| 4 | DC | Display data/command |
| 5 | CLK_EN | clk_wiz_1 resetn (set HIGH to enable MCLK/SCLK/LRCLK) |

GPIO[4:0] → `gpio_o_0[4:0]` → pins E13/E14/D14/T5/U5 (via ilslice_2)
GPIO[5] → `clk_wiz_1/resetn` via ilslice_1

## SPI CS Mapping
| CS | Dout_0 | Pin | Device |
|----|--------|-----|--------|
| CS0 | Dout_0[0] | V9 | Display (ILI9341) |
| CS1 | Dout_0[1] | V8 | Touch sensor |
| CS2 | Dout_0[2] | U6 | SD card |

## Audio Clocks (from clk_gen_0, enabled by GPIO5=1)
- SCLK → G22 (pin)
- LRCLK → G21 (pin)
- MCLK → 12.288 MHz from clk_wiz_1

## I²C Bus
- SCL → B20 (TWI clock)
- SDA → C14 (TWI data)
- Devices: CS42448 (0x48), Si5351A (0x60)

## PWM
- pwm_o_0[0] → T4

## RP2040 Zero UART Passthrough
- **Script:** `firmware/rp2040_uart_passthrough/main.py`
- GP0 = UART0 TX → FPGA RX (F19)
- GP1 = UART0 RX ← FPGA TX (B15)
- 19200 baud, 8N1, 3.3V logic
- Recovery: Bootsel + re-flash MicroPython

## Debug Console v2
- **Source:** `firmware/debug_console/main.c`
- **Binary:** `firmware/debug_console/elf.bin` (9,392 bytes)
- **Flash:** `JLinkExe -device RISC-V -if JTAG -speed 4000 -autoconnect 1 -JTAGConf "-1,-1" -CommanderScript flash.jlink`
- **Commands:** sys, clk, spi, gpio, i2c, pwm, help
- **SPI init:** prsc=4 (clk/128), CPOL=0, CPHA=0
- **TWI init:** prsc=4, cdiv=0, no clock stretching

## What's NOT on the current bitstream
- No sdin_0 (codec data input) — needs `neorv_basic_plus` design
- No aux_reset_in_0 (separate reset for clk_wiz_1) — clk enable via GPIO5 instead
- No Dout_1 group (separate GPIO port)