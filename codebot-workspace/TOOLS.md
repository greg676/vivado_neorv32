# TOOLS.md — CodecBot Paths & Commands

## Build & Flash (the proven method)
```bash
# Build firmware
cd ~/Desktop/designs/ptv2/vivado_neorv32/firmware/debug_console
make clean && make exe

# Flash via J-Link (1 MHz, wait 3-5s between attempts)
sleep 3
JLinkExe -device RISC-V -if JTAG -speed 1000 -autoconnect 1 \
  -JTAGConf "-1,-1" -CommanderScript flash.jlink

# flash.jlink contents:
#   r
#   halt
#   loadbin elf.bin 0x00000000
#   wreg pc 0x00000000
#   go
#   exit
```

## Console
- **Port:** `/dev/ttyUSB0` (Alchitry FTDI, NOT RP2040)
- **Baud:** 19200
- **Method:** Python serial — open once, keep connection, send multiple commands
```python
import serial, time
ser = serial.Serial('/dev/ttyUSB0', 19200, timeout=2)
ser.reset_input_buffer()
time.sleep(0.5)
ser.write(b'command\r')
ser.flush()
time.sleep(0.5)
data = ser.read(2000)
```

## J-Link Rules (from HARDWARE-DEBUG-RULES.md)
- Speed: 1000 kHz (1 MHz) — higher fails
- Wait 3-5s between J-Link sessions
- DO NOT use `r` after firmware is running (resets to bootloader)
- DO NOT use `neorv32_exe.bin` via J-Link (use `elf.bin`)
- DO NOT unbind FTDI USB interface (causes FPGA reset)
- **JTAG resetn gives direct reboot control** — always starts at exact SOT
- 3 failures in a row → STOP. Do not proceed without Claw. If FPGA is non-responsive after resets, critical fix needed.
- Power-cycle (unplug/replug USB) only to revert to flash design — rarely needed

## Toolchain
- `riscv-none-elf-gcc` (GCC 13.2.0, picolibc) — symlink to riscv64-unknown-elf-gcc
- OpenOCD 0.12.0 + J-Link for debug (`/tmp/openocd_neorv32_jlink.cfg`)

## Critic
- **Script:** `~/.openclaw-godbot/workspace/projects/critic/scripts/call_codecbot_critic.py`
- **Usage:** `--message-file /tmp/critic_plan.md` (the message file contains your Proposed Plan + Context + Source Data)
- **`--sync`:** Only when SOT source files changed. Overuse creates duplicate knowledge collections.

## Key Paths
| What | Where |
|------|-------|
| Firmware | `~/Desktop/designs/ptv2/vivado_neorv32/firmware/debug_console/` |
| Top-level RTL | `~/Desktop/designs/ptv2/vivado_neorv32/rtl/neorv_basic_plus_top.v` |
| Pin constraints | `~/Desktop/designs/ptv2/vivado_neorv32/constraints/ptv2_basic_plus.xdc` |
| Block design | `~/Desktop/designs/ptv2/vivado_neorv32/bd/neorv_basic_plus.bd` |
| Vivado project | `~/vivado_projects/alchirty_ptv2/pt_tf_neorv32/` |
| Last bitstream | `pt_tf_neorv32.runs/impl_1/` (find by timestamp: `ls -lt *.bit`) |
| Knowledge drops | `~/Desktop/designs/ptv2/docs/` |
| HARDWARE-DEBUG-RULES | `docs/HARDWARE-DEBUG-RULES.md` (in this workspace) |
