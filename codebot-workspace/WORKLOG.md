# WORKLOG.md — CodecBot Change Log
> Firmware version history, hardware changes, validated discoveries.
> **Facts live in PROJECT-STATUS-CANONICAL.md — this file records WHEN things changed.**
> Updated: 2026-06-20 (triad alignment reformat)

---

## Current Phase
**P1 — Bus Layer** (SPI arbiter, I²C, GPIO/PWM — all working in debug console)

---

## Current FPGA Build
**`neorv_basic_plus_top`** — loaded in FPGA, persists in flash (built 2026-06-18)
- See PROJECT-STATUS-CANONICAL.md §2 for full specs

---

## Firmware Version History

### v29 — debug_console (2026-06-18, current)
- Built for neorv_basic_plus_top (100 MHz CPU, DDR3 @ 0x20000000)
- UART on FTDI /dev/ttyUSB0 @ 19200 baud
- Commands: sys, i2c probe/r8/r16/w8/w16, codec init, clk on/off, pwm init/set/off, gpio dump/r/w/in, spi diag, spi flash id/sr/read, spi disp id/rst, spi touch, spi sd
- GPIO map: LED=bit0(G2), a0=bit1(E13), a1=bit2(E14), RSTCN=bit3(D14), RSTDN=bit4(T5), DC=bit5(U5), CLK_EN=bit6(internal), int_in=R4
- SPI CS: flash=CS0(V5), SD=CS1(U6), display=CS2(V9), touch=CS3(V8)
- I²C: CS42448 @ 0x4A, Si5351A @ 0x60 (deferred)
- LED blinks ~2s period, backlight PWM 50% at boot
- Display ID read returns 0x00 0x00 0x00 — hardware issue (5V vs 3.3V, or connection)

### Earlier versions (pre-workspace-purge, reference only)
- v28–v1: built for neorv_basic_top (160 MHz, RP2040 UART /dev/ttyACM0, no DDR3). GPIO bit 2=RST, bit 5=CLK_EN. Replaced by v29.

---

## Hardware Change Log

### 2026-06-18 — neorv_basic_plus_top deployed
- New bitstream built & loaded. Replaces neorv_ddr_wrapper.
- DDR3 MIG 256MB @ 0x20000000 verified (test patterns via OpenOCD)
- CPU @ 100 MHz (was 160 MHz in basic_top)
- UART moved to FTDI direct (/dev/ttyUSB0, was RP2040 /dev/ttyACM0)
- GPIO reorganized: RST→bit3, CLK_EN→bit6, added a0/a1 on bits 1/2
- MCLK 12.288 MHz confirmed via clk_wiz_1 MMCM
- CS42448 alive at I²C 0x4A, TDM init sequence working
- SPI: flash JEDEC ID read works, display probe returns 0x00 0x00 0x00
- JTAG OCD working (OpenOCD + J-Link: IDCODE 0x00000001, 1 hart, XLEN=32)
- Timing met: WNS +0.975ns, WHS +0.036ns

### 2026-06-16 — Memory map finalized
- Claw final: IMEM 128KB @ 0x00000000, DDR3 256MB @ 0x20000000, Flash @ 0x40000000 (unrealized), DMEM 128KB @ 0x80000000

### 2026-06-11 — neorv_basic_top (OBSOLETE)
- First working NeoRV32 bitstream on Pt V2
- UART on RP2040 /dev/ttyACM0, 160 MHz CPU, no DDR3
- GPIO: bit 2=RST, bit 5=CLK_EN
- Replaced by basic_plus_top 2026-06-18

### 2026-05-20 — neorv_ddr_wrapper (OBSOLETE)
- First DDR3 attempt. DMEM/DDR3 collision at 0x80000000.
- Replaced by basic_plus_top.

---

## Verified-Good (✅)
- Bitstream builds & timing-met (WNS +0.975ns, WHS +0.036ns)
- DDR3 MIG @ 0x20000000 working (test patterns verified via OpenOCD)
- JTAG OCD working (OpenOCD + J-Link: IDCODE 0x00000001, 1 hart, XLEN=32)
- MCLK = 12.288 MHz confirmed
- CS42448 alive at I²C 0x4A, ChipID=0x04, TDM init sequence working
- SPI: flash JEDEC ID read works (CS0=V5), display probe (CS2=V9), SD/touch mapped (CS1=U6, CS3=V8)
- GPIO: LED blink, backlight PWM 50%, RSTCN control, RSTDN reset sequence
- UART fully responsive, no dropped chars
- J-Link flash method proven (1 MHz, elf.bin, wait 3-5s)
- sd_in_1_0 and sd_out_1_0 IP built & tested (not in current build)
- All 42 FT601 signals pin-mapped (not in block design)
- Pin map LOCKED in PROJECT-STATUS-CANONICAL.md

---

## Top Open Tasks
1. ⬜ **Fix CLOCK_FREQUENCY** — was 160 MHz, actual 100 MHz. Claw re-synth in progress.
2. ⬜ **Display debug** — ILI9341 returns 0x00 0x00 0x00 (5V vs 3.3V, or connection)
3. ⬜ **Solder flash + MCLK** — Claw working on this
4. ⬜ **SD card probe** — SPI CS1=U6
5. ⬜ **Touch probe** — SPI CS3=V8, PENIRQ on gpio_i[0]=R4
6. ⬜ **Execute comprehensive planner** — feed PLANNER-PROMPT.md to AI for detailed phase plan
7. ⬜ **P2: Wire sd_in/sd_out** into block design, map to NeoRV32, FIFO+IRQ
8. ⬜ **P5: Wire FT601 IP** into block design, TDM↔FT601 CDC

---

## 📥 OPERATOR DIRECTIVES
<!-- Claw pastes directives here. Codecbot promotes to top of open tasks. -->
