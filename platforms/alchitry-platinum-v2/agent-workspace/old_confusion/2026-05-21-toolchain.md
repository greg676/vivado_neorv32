# Session: 2026-05-21 17:10 PDT — Toolchain Notes & Structure

## SES RISC-V 7.32a — What It Actually Is

This is the **legacy RISC-V-only edition** (not the unified ARM+RISC-V v8.x). That means:
- **RISC-V targets only** — no ARM Cortex-M support in this version
- Three GCC toolchains bundled: riscv32-none-elf, andes-riscv32-none-elf, corev-riscv32-none-elf
- SEGGER's own linker (`.icf` scripts) — not GNU ld
- Uses internal `cc` wrapper, not `riscv32-none-elf-gcc`
- Cannot debug ARM MCUs (SAMD21, RP2040, STM32) from this SES version

### SES Directory Structure
```
/usr/share/segger_embedded_studio_for_risc-v_7.32a/
├── bin/          # emStudio, emBuild, cc, emLicense, emScript
├── gcc/          # riscv32-none-elf, andes-riscv32-none-elf, corev-riscv32-none-elf
│   └── <target>/bin/  # as, ld, nm, objcopy, objdump (but NO gcc binary!)
├── html/         # Documentation
├── include/      # SEGGER library headers
├── lib/          # Libraries
├── llvm/         # LLVM/bin for code analysis
├── samples/      # Template projects, linker scripts (.icf), crt0
├── source/       # Source for SEGGER libraries
└── targets/      # RISC-V target definitions, build options
```

### The "no standalone GCC" problem
SES does not ship `riscv32-none-elf-gcc` as a standalone binary. It has `cc1` (compiler proper), `as` (assembler), `ld` (linker) but uses its own `cc` wrapper. This means:
- **Within SES**: everything works — `emBuild` drives the toolchain
- **Outside SES**: can't do `riscv32-none-elf-gcc -o foo.elf foo.c` on command line
- **NeoRV32 bootloader compilation**: requires standalone GCC or we port the Makefile to emBuild

### Getting standalone RISC-V GCC options:
1. Pre-built from Embecosm/SiFive releases
2. Build from `riscv-gnu-toolchain` source
3. Use SES's emBuild to drive NeoRV32 builds (would need project files)

## J-Link EDU Mini V2 Compatibility

### Confirmed working:
- J-Link Software v9.44 recognizes it
- Firmware auto-updated to latest (May 13 2026)
- EDU Mini V2 supports: **JTAG, SWD, SPI flash programming**
- Licenses active: FlashBP (Flash Breakpoints), GDB (GDB Server)
- This is fully compatible with SES for RISC-V debugging

### EDU Mini V2 limitations (vs full J-Link):
- No J-Trace (streaming trace)
- No Ethernet interface
- Limited to non-commercial use (educational/personal projects)
- Some advanced features may be restricted

### For ARM MCU testing (SAMD21, RP2040, STM32):
- **J-Link hardware supports SWD** — the probe itself works fine
- **SES 7.32a is RISC-V only** — cannot target ARM from this IDE
- Use `JLinkExe` + `JLinkGDBServer` + GNU ARM GCC for ARM debugging
- Or would need SES v8.x unified edition for ARM+RISC-V in one IDE

### For NeoRV32 specifically:
- Connect J-Link JTAG to the Alchitry board JTAG pins:
  - TCK → AB22, TDI → E3, TDO → M2, TMS → J6
- NeoRV32 OCD uses standard RISC-V debug module over JTAG
- SES can debug NeoRV32 firmware via J-Link — full source-level debug
- Bitstream must be loaded first (Vivado), then SES connects to running NeoRV32

## Ozone 3.40i
- Installed at `/opt/SEGGER/Ozone_V340i/`
- GUI debugger that works with J-Link
- Supports RISC-V targets
- Can be used standalone or launched from SES

## What We Need Next
1. Standalone RISC-V GCC for NeoRV32 bootloader compilation
2. SES project template for NeoRV32 firmware
3. ARM MCU connected to J-Link for SWD test (verify probe works on known target)
4. NeoRV32 bitstream loaded on Alchitry board for live debug test
