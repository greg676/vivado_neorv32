# Recorder/Player Overlay — Plan

## Date: 2026-06-10
## Block Design: `neorv_codec`

---

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           Alchitry Pt V2 (XC7A100T)      │
                    │                                          │
  100 MHz (W19) ───┤→ clk_wiz_0 (MMCM)                        │
                    │   ├─ 160 MHz → NeoRV32 sys_clk           │
                    │   └─ 12.288 MHz → clk_gen MCLK           │
                    │                                          │
  RP2040 (UART) ───┤→ NeoRV32 UART0 (F19/B15) [debug console] │
  J-Link (JTAG) ───┤→ NeoRV32 OCD (Y3/AA3/AA1/AB1)           │
                    │                                          │
  CS42448 ◄────────┤→ I²C (B21/E21) [config @ 0x48]           │
   TDM DIN ────────┤→ sd_in TDM AXIS → SLINK RX [6ch ADC]     │
   TDM DOUT ◄──────┤← SLINK TX → AXIS → TDM OUT [8ch DAC]     │
   MCLK ◄──────────┤← clk_gen (D16) [12.288 MHz]              │
   SCLK ◄──────────┤← clk_gen (A19) [12.288 MHz]              │
   LRCLK ◄─────────┤← clk_gen (A18) [48 kHz]                  │
                    │                                          │
  Si5351A ◄────────┤→ I²C (B21/E21) [config @ 0x60]           │
                    │                                          │
  ILI9341 ◄────────┤→ SPI0 (CS0) [320×240 display]            │
  XPT2046 ◄────────┤→ SPI0 (CS1) [touch controller]           │
  SD Card ◄────────┤→ SPI0 (CS2) [FAT32 storage]              │
                    │                                          │
  GPIO ────────────┤→ DC, RST, BL, T_IRQ [display control]    │
  PWM ────────────┤→ Backlight dimming                        │
                    └─────────────────────────────────────────┘
```

## NeoRV32 IP Configuration

| Generic | Value | Purpose |
|---------|-------|---------|
| CLOCK_FREQUENCY | **160000000** | Fix 100→160 MHz mismatch |
| RISCV_ISA_M | true | Hardware multiply (FatFs, DSP) |
| RISCV_ISA_C | true | Compressed instructions (code density) |
| RISCV_ISA_Zicond | true | Conditional moves |
| IMEM_SIZE | 131072 (128 KB) | Firmware |
| DMEM_SIZE | 131072 (128 KB) | Data + stack + buffers |
| ICACHE_EN | true | 4-block I-cache |
| DCACHE_EN | true | 4-block D-cache |
| IO_UART0_EN | true | Debug console @ 19200 baud |
| IO_TWI_EN | true | I²C for CS42448 + Si5351A |
| IO_SPI_EN | true | Display + touch + SD card |
| IO_SPI_FIFO | 8 | Burst SPI for display/SD |
| IO_GPIO_EN | true | Display control signals |
| IO_GPIO_OUT_NUM | 4 | DC, RST, BL, T_IRQ |
| IO_PWM_EN | true | Backlight PWM |
| IO_PWM_NUM | 1 | — |
| IO_SLINK_EN | true | AXI4-Stream codec data path |
| IO_SLINK_RX_FIFO | 32 KB | ADC buffer (8192 samples) |
| IO_SLINK_TX_FIFO | 32 KB | DAC buffer (8192 samples) |
| IO_DMA_EN | true | DMA for SLINK ↔ DMEM |
| IO_CLINT_EN | true | Timer interrupts |

## Block Design Components

| IP | Type | Function |
|----|------|----------|
| neorv32_vivado_ip | RISC-V | RV32IMC + Zicond, 128/128 KB, all periphs |
| clk_wiz_0 | Xilinx MMCM | 100 MHz → 160 MHz sys + 12.288 MHz audio |
| clk_gen | custom HDL | Generates SCLK/LRCLK/WCLK from MCLK |
| sd_in_codec_master_stream | custom HDL | TDM RX → AXI4-Stream (double-buffered) |
| sd_out_codec_master_stream | custom HDL | AXI4-Stream → TDM TX (double-buffered) |
| proc_sys_reset | Xilinx | Reset sequencer |

## Pin Map

| Signal | FPGA Pin | IO Std | Direction | Notes |
|--------|----------|--------|-----------|-------|
| **System** |||||
| clk | **W19** | LVCMOS33 | in | 100 MHz board osc |
| resetn | **N15** | LVCMOS33 | in | Active-low reset button |
| **JTAG** |||||
| jtag_tck | **Y3** | LVCMOS33 | in | J-Link TCK |
| jtag_tdi | **AA3** | LVCMOS33 | in | J-Link TDI |
| jtag_tdo | **AA1** | LVCMOS33 | out | J-Link TDO |
| jtag_tms | **AB1** | LVCMOS33 | in | J-Link TMS |
| **UART (RP2040 debug)** |||||
| uart0_rxd | **F19** | LVCMOS33 | in | ← RP2040 GP0 |
| uart0_txd | **B15** | LVCMOS33 | out | → RP2040 GP1 |
| **I²C** |||||
| scl | **B21** | LVCMOS33 | inout | CS42448 (0x48) + Si5351A (0x60) |
| sda | **E21** | LVCMOS33 | inout | 2.2k pull-ups required |
| **Audio TDM** |||||
| mclk | **D16** | LVCMOS33 | out | 12.288 MHz → CS42448 |
| sclk | **A19** | LVCMOS33 | out | 12.288 MHz bit clock |
| lrclk | **A18** | LVCMOS33 | out | 48 kHz frame sync |
| din | **A21** | LVCMOS33 | in | TDM data from CS42448 ADC |
| dout | **D21** | LVCMOS33 | out | TDM data to CS42448 DAC |
| **SPI (Display + Touch + SD)** |||||
| spi_sck | TBD | LVCMOS33 | out | Shared SPI clock |
| spi_mosi | TBD | LVCMOS33 | out | Shared SPI MOSI |
| spi_miso | TBD | LVCMOS33 | in | Shared SPI MISO |
| disp_cs | TBD | LVCMOS33 | out | ILI9341 chip select |
| touch_cs | TBD | LVCMOS33 | out | XPT2046 chip select |
| sd_cs | TBD | LVCMOS33 | out | SD card chip select |
| **Display Control** |||||
| disp_dc | TBD | LVCMOS33 | out | Data/Command |
| disp_rst | TBD | LVCMOS33 | out | Display reset |
| disp_bl | TBD | LVCMOS33 | out | Backlight enable |
| touch_irq | TBD | LVCMOS33 | in | Touch interrupt |

## Clock Summary

| Clock | Source | Freq | Drives |
|-------|--------|------|--------|
| sys_clk | clk_wiz_0 clkout0 | 160 MHz | NeoRV32 CPU, AXI, peripherals |
| audio_mclk | clk_wiz_0 clkout1 | 12.288 MHz | clk_gen → SCLK/LRCLK + CS42448 MCLK |

## Data Flow

### Recording (6ch ADC → SD Card)
```
CS42448 ADC → TDM SDOUT → sd_in (double-buffer) → AXIS → SLINK RX
  → NeoRV32 DMA → DMEM buffer → FatFs → SPI → SD Card (WAV file)
```

### Playback (SD Card → 8ch DAC)
```
SD Card → SPI → FatFs → DMEM buffer → NeoRV32 DMA
  → SLINK TX → AXIS → sd_out (double-buffer) → TDM SDIN → CS42448 DAC
```

### Bandwidth
| Path | Rate | Notes |
|------|------|-------|
| TDM audio | 9.216 Mbps (48k×8ch×24bit) | Continuous, handled by fabric DMA |
| SD card SPI | ~12.5 Mbps (25 MHz / 2) | Bursty, SD spec max |
| Display SPI | ~40 Mbps | Bursty, 30ms/full redraw |
| I²C config | ~100 kbps | Init-only |
| UART debug | 19200 baud | Console prints |

## Software Stack

### Firmware (NeoRV32 bare-metal C)
1. **Boot:** Init clocks, I²C → configure Si5351A + CS42448
2. **Display:** ILI9341 driver (framebuffer in DMEM or SPI direct)
3. **Touch:** XPT2046 poll (touch coordinates)
4. **SD Card:** FatFs library → FAT32 read/write
5. **Audio:** DMA-managed SLINK transfers, ring buffers in DMEM
6. **UI:** Menu system on display, touch-driven transport controls

### Build System
- NeoRV32 Makefile-based (like hello_uart)
- Toolchain: Vitis riscv32-xilinx-elf-gcc (wrappers in tools/)
- Load via J-Link JTAG: `loadfile → set PC → go`

## Implementation Phases

### Phase 1: Codec Alive ⏭
- neorv_codec block design with SLINK + TDM IP
- clk_gen generates SCLK/LRCLK from 12.288 MHz MCLK
- I²C init sequence for CS42448 + Si5351A
- Verify: scope check SCLK/LRCLK/DIN/DOUT

### Phase 2: Audio Loopback
- sd_in → SLINK RX → DMA → DMEM → DMA → SLINK TX → sd_out
- NeoRV32 firmware: DMA descriptor setup, ring buffer
- Verify: analog loopback (DAC→ADC), 1 kHz tone test

### Phase 3: SD Card + Display
- SPI to ILI9341 + XPT2046 (pin assignment TBD)
- FatFs integration for SD card
- Display: level meters, transport controls

### Phase 4: Full Recorder/Player
- Record: ADC → SLINK → DMA → ring buffer → WAV write to SD
- Playback: WAV read from SD → ring buffer → DMA → SLINK → DAC
- UI: touch-driven record/play/stop, file browser, meters
