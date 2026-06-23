# CS42448 I²C Bring-up — Validated 2026-06-17

**Status:** ✅ Fully working on Alchitry Pt V2 + neorv_basic_top bitstream

## Hardware

| Item | Detail |
|---|---|
| **FPGA** | XC7A100T-FGG484-2 (Alchitry Pt V2) |
| **MCU** | NeoRV32 RV32IM+Zicond, 160 MHz |
| **Codec** | CS42448 on Br breakout board |
| **I²C bus** | SCL=B20, SDA=C14 (TWI peripheral) |
| **Bus speed** | ~1.22 kHz (slow but reliable) |
| **Codec I²C address** | 0x48 (AD1=0, AD0=0) |

## Reference: Known-Working Library Patterns

Three patterns validated and cross-referenced:

### 1. audiobot's proven CS42448 init (from Arty Z7-20 project)
- Used as the ground truth for TDM register values
- Stored in `/home/greg-jack/.openclaw-audio-companion/workspaces/audiobot/memory/`
- Key insight: **reg 0x04 = 0x36** for TDM mode (not the default 0x01 = Left-Justified)
- The debug_console uses a variant: **FUNCMOD=0xF001** which packs the TDM config differently

### 2. Teensy / Arduino CS42448 library patterns
- Standard 16-bit register writes (high byte, then low byte)
- Always clear PDN (Power Down) register LAST
- Read-back to verify each write succeeded

### 3. debug_console v27 (the firmware we just ran)
- Full TDM init sequence
- 16-bit register writes via `i2c_write16()`
- `neorv32_twi_setup(6, 15, 0)` for reliable I²C at ~1.2 kHz

## NeoRV32 TWI Setup — The Working Parameters

```c
// CRITICAL: These are the only parameters that worked reliably
neorv32_twi_setup(6, 15, 0);
//           |  |  |
//           |  |  └── clkstr_en: 0 (no clock stretching)
//           |  └───── cdiv: 15 (clock divider)
//           └──────── prsc: 6 (prescaler index → clk/2048)
```

**Resulting I²C clock:** f_twi = 160,000,000 / (2048 × 16 × 4) ≈ **1,220 Hz**

**Why so slow?** The NeoRV32 TWI implementation needs very slow clocks for reliable operation at this bitstream. The Arty Z7-20 ran at 400 kHz but that used a different clock tree. 1.2 kHz is fine for configuration reads/writes.

## CS42448 Register Map (16-bit, accessed via I²C write16/read16)

| Reg | Default | Init Value | Description |
|------|---------|-----------|-------------|
| 0x01 | — | read | Chip ID (expect 0x04 for CS42448) |
| 0x02 | 0x00 | 0x0000 | **Power Control (PDN)** — 0 = all powered up |
| 0x03 | 0xF0 | 0xF001 | **Functional Mode** — TDM, slave, one-line |
| 0x04 | 0x01 | (n/a) | Interface Control 2 (DIF) — packed into FUNCMOD |
| 0x05 | 0x00 | (n/a) | ADC Control |
| 0x06 | 0x00 | 0x0077 | **TDM Mode** — 8 slots, one-line TDM |
| 0x07 | 0xE4 | 0xE400 | **ADC Mux** — route AIN1→ADC1, etc. |
| 0x08-0x0A | 0x00 | 0x0000 | **PGA gain** — unity (0dB) |
| 0x0B | 0x00 | 0x0000 | **DAC Mute** — unmute all |
| 0x18-0x1F | 0x00 | 0x0000 | **DAC volume** — 0dB |

**Key: clear PDN (reg 0x02 = 0x0000) LAST.** In this build it's already 0x0000 on power-up, so no action needed.

## GPIO Control Pins (Br breakout)

| GPIO Bit | Pin | Function | Active State |
|----------|-----|----------|--------------|
| G[0] | E13 | A0 (codec AD0) | HIGH for I²C addr 0x48 |
| G[1] | E14 | A1 (codec AD1) | LOW for I²C addr 0x48 |
| G[2] | D14 | RSTCN (codec reset) | **HIGH = de-assert** |
| G[3] | T5 | RSTDN (display reset) | HIGH = de-assert |
| G[4] | U5 | DC (display data/command) | — |
| G[5] | (internal) | CLK_EN (clk_wiz_1 resetn) | **HIGH = clocks running** |

**Critical sequence:**
1. Set G[2] = 1 (de-assert codec RST)
2. Set G[5] = 1 (enable MCLK/SCLK/LRCLK)
3. Run I²C init sequence

## Clock Generator (clk_gen_0 custom IP)

The design includes a custom `clk_gen` IP that generates SCLK and LRCLK for the codec:

```verilog
// clk_gen.v - TDM clock generator
// MCLK = clk_wiz_0 (100 MHz system clock)
// SCLK = gated MCLK, 12.288 MHz when enabled
// LRCLK = 1-cycle pulse at Fs (48 kHz)
// go = clk_wiz_1_locked (enables output when 12.288 MHz MMCM is locked)
```

**Clock tree:**
- `clk_wiz_0` → 100 MHz (system) → feeds `clk_gen.MCLK`
- `clk_wiz_1` → 12.288 MHz (audio) → locked signal → `clk_gen.go`
- When `clk_wiz_1` locks: SCLK and LRCLK start toggling
- GPIO5 = `clk_wiz_1` resetn (HIGH = running)

**Result:** `clk on` (GPIO5=1) enables the 12.288 MHz MMCM. Once locked, SCLK (G22) and LRCLK (G21) start toggling. These feed the CS42448 codec.

## MCLK Question

> "i dont have the mclk connected rn, i thought it was an output?"

The codec needs an MCLK input (master clock, 12.288 MHz for 48 kHz sample rate). On the Br breakout:
- If MCLK is an **output from the FPGA** → it comes from the clocking wizard (clk_wiz_1) to pin D16
- If MCLK is an **input to the codec** → it needs to be generated externally

The current design has clk_wiz_1 generating 12.288 MHz. This is gated by GPIO[5] (CLK_EN). Once enabled, MCLK should appear at pin D16. Check the Br schematic to confirm MCLK routing direction.

If MCLK is connected FPGA→Codec: `clk on` enables it. If MCLK is disconnected: the codec won't generate SCLK/LRCLK and TDM framing will fail.

## UART Commands (debug_console v27)

```
> sys
clk:160000000 IMEM:131072 DMEM:131072

> i2c scan
scan: 0x48
found=1

> i2c read8 0x48 0x01
0x04

> i2c read16 0x48 0x03
0xF001

> i2c write8 0x48 0x04 0x36
write ok

> codec init
--- CS42448 TDM init (v27) ---
Reset: RST=0... RST=1... ok
Clocks: GPIO5=1... ok
Bus: SCL=H SDA=H OK
ChipID (0x01): 0x0400
Arty-style init:
  PWRCTL=0x0000: read 0x0000
  FUNCMOD=0xF001: read 0xF001
  TDM=0x0077 (8 slots): read 0x0077
  ADCMUX=0xE400: read 0xE400
  PGA unity... ok
  DACMUTE=0x0000: read 0x0000
  DAC vol 0dB... ok
=== CS42448 ready ===
TDM: 8-slot, slave, one-line

> gpio w 2 1
G[2]=1
> clk on
clk on
```

## What I Got Wrong (Lessons)

1. **J-Link direct TWI register pokes don't work.** The TWI state machine needs continuous clock cycles from a RUNNING CPU. When halted via J-Link, START/STOP/data state transitions stall. Always use the debug_console firmware (loaded via J-Link) and UART commands for I²C work.

2. **IO_GPIO_DIR_EN=false** locks all GPIO to input direction, but the output register still drives the physical pins (the wrapper hard-wires gpio_o_0 as outputs). The `neorv32_gpio_pin_get()` function reads the input register, so `gpio dump` shows input state, not output drive. If output pin isn't physically connected to anything, the input reads back as 0.

3. **The stale XDC files in vivado_projects/** (`ptv2_basic.xdc`, `ptv2_basic_plus.xdc`) had wrong JTAG pin mappings. The **real pin map** is in `/home/greg-jack/Desktop/alchitry.xdc` (the original Alchitry board file). The built bitstream uses the correct pins.

4. **My first I²C probe attempt with prsc=3, cdiv=5 failed** because the NeoRV32 TWI needs the proven `prsc=6, cdiv=15` for reliable operation.

## Build / Flash Sequence

```bash
# 1. Make sure bitstream is loaded
# neorv_basic_top.bit is already on the FPGA

# 2. Flash debug_console firmware via J-Link
cat > /tmp/flash.txt << 'EOF'
connect
loadbin /home/greg-jack/Desktop/designs/ptv2/vivado_neorv32/firmware/debug_console/elf.bin 0x00000000
wreg pc 0x00000000
go
exit
EOF
JLinkExe -device RV32 -if JTAG -speed 4000 -autoconnect 1 -NoGui 1 \
  -CommandFile /tmp/flash.txt -jtagconf -1,-1

# 3. Open UART at 19200 baud
python3 -c "import serial; s = serial.Serial('/dev/ttyACM0', 19200, timeout=2); 
import time; time.sleep(1); s.write(b'codec init\r\n'); time.sleep(5); 
print(s.read(2048).decode())"
```

## What's Next

1. ✅ I²C to CS42448 validated
2. ✅ TDM register config written and verified
3. ⬜ **Verify SCLK/LRCLK are toggling** (need MCLK to be running)
4. ⬜ **Connect MCLK** if not already routed on Br
5. ⬜ **Connect SDIN** (E18) — codec audio data → FPGA
6. ⬜ **Connect SDOUT** (F18) — FPGA → codec audio data
7. ⬜ **Generate a test tone** and verify it loops back
8. ⬜ **Move to DDR3 audio buffers** (needs neorv_basic_plus bitstream)
9. ⬜ **Wire FT601** for USB audio streaming
10. ⬜ **Touch UI** for transport controls
