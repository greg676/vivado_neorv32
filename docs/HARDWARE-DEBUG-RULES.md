# Hardware Debugging — Do/Do-Not List

> **RULE:** Before any hardware action, scan this list. If you're about to do something on the DO NOT side, stop and reconsider.
> Last updated: 2026-06-19 11:08 PDT (v30 — added I²C pins, UART pins, clock info)

---

## ✅ DO (these work — PROVEN)

### Firmware Loading (THE ONLY METHOD THAT WORKS)
```bash
# 1. Build
cd /home/greg-jack/Desktop/designs/ptv2/vivado_neorv32/firmware/debug_console
make clean && make exe

# 2. Flash via J-Link — CRITICAL: 1 MHz JTAG, wait 3-5s between attempts
#    DO NOT retry rapidly. DO NOT open/close port repeatedly.
sleep 3
JLinkExe -device RISC-V -if JTAG -speed 1000 -autoconnect 1 \
  -JTAGConf "-1,-1" -CommanderScript flash.jlink

# flash.jlink contents (MUST be exactly this):
#   r
#   halt
#   loadbin /home/greg-jack/Desktop/designs/ptv2/vivado_neorv32/firmware/debug_console/elf.bin 0x00000000
#   wreg pc 0x00000000
#   go
#   exit

# 3. Open terminal at 19200 baud on /dev/ttyUSB0
#    Use Python serial — ONE connection, keep it open, send commands
```

### UART Communication (Python serial — keep connection open)
```python
import serial, time
ser = serial.Serial('/dev/ttyUSB0', 19200, timeout=2)
ser.reset_input_buffer()
time.sleep(0.5)  # let firmware boot
ser.write(b'command\r')
ser.flush()
time.sleep(0.5)
data = ser.read(2000)
print(data.decode('ascii', errors='replace'))
# Keep ser open for more commands — do NOT close/reopen between commands
ser.close()  # only when done
```

### J-Link Connection Rules
- **Speed: 1000 kHz (1 MHz)** — higher speeds cause intermittent JTAG failures
- **Wait 3-5 seconds** between J-Link sessions — target needs time to recover
- **First connect may fail** — J-Link auto-retries internally, usually succeeds on 2nd attempt
- **DO NOT run back-to-back J-Link scripts** — each `r` resets the target, too many resets destabilize the TAP
- **VTref should be ~3.3V** — if it drops to 1.4V, board needs power cycle

---

## ❌ DO NOT (these fail or break things)

### 1. DO NOT unbind the FTDI USB interface
```bash
# THIS CAUSES FPGA RESET - the board reboots back to bootloader!
echo "1-1.1:1.1" | sudo tee /sys/bus/usb/drivers/usb/unbind
```

### 2. DO NOT use `r` (reset) in J-Link after firmware is running
The `r` command resets to bootloader, losing firmware. Only use `r` BEFORE `loadbin`.

### 3. DO NOT use `neorv32_exe.bin` via J-Link
The 8-byte bootloader header gets executed as code → crash. Use `elf.bin` (raw binary).

### 4. DO NOT use J-Link speed > 1000 kHz
Higher speeds (4000+) cause "Failed to measure TotalIRLen" and intermittent connection failures.

### 5. DO NOT open/close UART port repeatedly
Rapid open/close can cause FTDI resets. Open once, keep connection, send multiple commands.

### 6. DO NOT use `neorv32_gpio_pin_get()` to read output pin state
It reads PORT_IN (gpio_i from fabric). In basic_plus_top, only int_in (touch PENIRQ) is wired to gpio_i. Use direct register read: `NEORV32_GPIO->PORT_OUT`.

### 7. DO NOT confuse the two bitstreams
- `neorv_basic_top` → UART on RP2040 `/dev/ttyACM0`, GPIO bit 2=RST, bit 5=CLK_EN
- `neorv_basic_plus_top` → UART on FTDI `/dev/ttyUSB0`, GPIO bit 3=RSTCN, bit 6=CLK_EN

### 8. DO NOT assume GPIO direction is configurable
`IO_GPIO_DIR_EN=false` in the BD means NO direction register. `gpio_o` pins are ALWAYS outputs, `gpio_i` pins are ALWAYS inputs. Direction is fixed by which physical port they're wired to in the block design.

### 9. DO NOT use the wrong NeoRV32 source tree
- `neorv32-main` → produces `NEO!` header (different image format)
- The debug_console build uses `neorv32-main` → works with J-Link direct loadbin

### 10. DO NOT run long-running Python serial scripts
Process gets SIGKILLed. Use short scripts (one command, exit immediately).

### 11. DO NOT hammer J-Link with rapid retries
Each failed connect destabilizes the JTAG TAP further. Wait 5+ seconds between attempts. If 3 attempts fail, power-cycle the board.

---

## 🔧 Recovery Procedures

### If firmware is lost (bootloader running):
```bash
sleep 3
JLinkExe -device RISC-V -if JTAG -speed 1000 -autoconnect 1 \
  -JTAGConf "-1,-1" -CommanderScript flash.jlink
```

### If J-Link connection fails repeatedly:
- Wait 5+ seconds between attempts
- Check VTref (should be 3.3V)
- If VTref = 1.4V → board needs power cycle
- 3 failures in a row → power-cycle the board

### If FTDI serial disappears (`/dev/ttyUSB0` gone):
- Check `lsusb` for FTDI device
- If Vivado hw_server is running, it may claim the interface

### If the board seems dead:
- Power-cycle (unplug/replug USB)
- Check J-Link VTref after power cycle

---

## 📝 I²C Pins (CANONICAL — from PROJECT-STATUS-CANONICAL.md)

| Signal | FPGA Pin | Notes |
|--------|----------|-------|
| SCL | **B21** | I²C clock — NOT B20 (that was old basic_top) |
| SDA | **E21** | I²C data — NOT C14 (that was old basic_top) |

**Devices on bus:** CS42448 at 0x4A (a1=HIGH shifts from 0x48), Si5351A at 0x60 (deferred)

## 📝 UART Pins (basic_plus_top)

| Signal | FPGA Pin | Notes |
|--------|----------|-------|
| RX | **AA20** | FTDI direct — NOT F19 (old basic_top) |
| TX | **AA21** | FTDI direct — NOT B15 (old basic_top) |

**Console:** `/dev/ttyUSB0` @ 19200 baud. NOT `/dev/ttyACM0` (that was RP2040 on old basic_top).

## 📝 Clock Info

| Clock | Frequency | Source |
|-------|-----------|--------|
| CPU (ui_clk) | **100 MHz** | MIG ui_clk — NOT 160 MHz (old CLOCK_FREQUENCY constant) |
| MCLK | **12.288 MHz** | clk_wiz_1 MMCM: 100 MHz × 48/(78.125×5) |
| SCLK | from clk_gen_0 | TDM bit clock (derived from MCLK) |
| LRCLK | from clk_gen_0 | TDM frame sync (FSYNC) |

## 📝 GPIO Pin Map (neorv_basic_plus_top — v30 CORRECTED)

| Bit | Name | Pin | Direction | Function |
|-----|------|-----|-----------|----------|
| 0 | LED | G2 | OUT (gpio_o) | On-board LED, active HIGH |
| 1 | a0 | E13 | OUT (gpio_o) | CS42448 I²C address LSB |
| 2 | a1 | E14 | OUT (gpio_o) | CS42448 I²C address MSB |
| 3 | RSTCN | D14 | OUT (gpio_o) | Codec reset, active HIGH |
| 4 | RSTDN | T5 | OUT (gpio_o) | Display reset, active HIGH |
| 5 | DC | U5 | OUT (gpio_o) | Display data/command |
| 6 | CLK_EN | (int) | OUT (gpio_o) | Clock gen enable, HIGH=running |
| — | int_in | R4 | IN (gpio_i) | Touch PENIRQ (XPT2046) |

**GPIO registers (NEORV32_GPIO_BASE = 0xFFFC0000):**
- Offset 0x00: PORT_IN (read-only) — reads gpio_i pins from fabric
- Offset 0x04: PORT_OUT (read/write) — drives gpio_o pins to fabric
- No DIR register (IO_GPIO_DIR_EN=false)

## 📝 SPI CS Map (neorv_basic_plus_top — from impl_1 io_placed.rpt)

| CS Index | spi_cs bit | Pin | Device |
|----------|-----------|-----|--------|
| CS0 | spi_cs[0] | V5 | W25Q64 flash |
| CS1 | spi_cs[1] | U6 | SD card |
| CS2 | spi_cs[2] | V9 | ILI9341 display |
| CS3 | spi_cs[3] | V8 | XPT2046 touch |

**Source of truth:** Vivado `neorv_basic_plus_top_io_placed.rpt` — NOT the stale XDC.

## 📝 Key Bitstream Differences

| Feature | basic_top | basic_plus_top |
|---------|-----------|----------------|
| Build date | June 11 | June 18 |
| UART pins | F19/B15 (Br) | AA20/AA21 (FTDI) |
| Console port | /dev/ttyACM0 | /dev/ttyUSB0 |
| CPU clock | 160 MHz | 100 MHz |
| GPIO: RST | bit 2 | bit 3 |
| GPIO: CLK_EN | bit 5 | bit 6 |
| GPIO: a0/a1 | none | bits 1/2 |
| DDR3 | No | Yes (256MB @ 0x20000000) |
| IMEM | 128KB RAM | 128KB RAM |
| DMEM | 128KB RAM | 128KB RAM |

---

## 🎯 Current State (2026-06-19 04:57 PDT)

- **Bitstream:** `neorv_basic_plus_top.bit` (loaded, persists in flash)
- **Firmware:** debug_console v29 (17.5KB, built and flashed)
- **Console:** `/dev/ttyUSB0` @ 19200 baud
- **Working:** sys, i2c scan/probe/r/w, codec init, pwm init/set, gpio dump/r/w/in, clk on/off, spi diag, spi flash id/sr/read
- **LED:** blinks ~2s period (no UART interference)
- **Backlight:** 50% at boot (PWM ch0, duty 127/255)
- **Display:** RSTDN reset sequence at boot, but ID read returns 0x00 0x00 0x00 — hardware issue (5V vs 3.3V, or connection)
- **Flash:** not soldered yet
- **SD:** not tested
- **Touch:** not tested

## 📝 Debug Console Commands (v29)

```
sys                  - system info
i2c probe            - scan 0x00-0x7F
i2c r8 A R           - read 8-bit register
i2c w8 A R V         - write 8-bit register
i2c r16 A R          - read 16-bit register (CS42448)
i2c w16 A R V        - write 16-bit register (CS42448)
codec init           - full CS42448 TDM init sequence
clk on|off           - codec clock enable (GPIO6)
pwm init|set <0-100>|off  - backlight PWM control
gpio dump            - show OUT and IN registers
gpio r P             - read output pin P (PORT_OUT)
gpio in P            - read input pin P (PORT_IN)
gpio w P V           - write output pin P to V
spi diag             - SPI diagnostic (CS0 flash test)
spi flash id         - read W25Q64 JEDEC ID
spi flash sr         - read W25Q64 status register
spi flash read A L   - read L bytes from flash addr A
spi disp id          - read ILI9341 display ID
spi disp rst         - reset display (RSTDN LOW→HIGH)
spi touch            - read XPT2046 touch X/Y
spi sd               - probe SD card
```
