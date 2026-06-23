# NeoRV32 Framework Deep Dive

## Location
`/home/greg-jack/vivado_projects/neorv32-main/` — full source tree, no git connection (zip extraction)

## Structure

```
neorv32-main/
├── rtl/
│   ├── core/              # CPU core VHDL (neorv32_bootloader_image.vhd is pre-built)
│   ├── system_integration/ # Vivado IP packaging (neorv32_vivado_ip.tcl)
│   │   └── xbus2axi4_bridge.vhd  # XBUS → AXI4 bridge (this is how the SoC talks AXI!)
│   ├── test_setups/        # Reference SoC top-levels for different configs
│   └── verilog/            # Verilog equivalents for some modules
├── sw/
│   ├── bootloader/         # Bootloader source + makefile (builds to .vhd image)
│   │   ├── config.h        # Auto-boot settings, UART, SPI/TWI flash support
│   │   └── main.c          # Bootloader logic: wait timeout → try flash → console
│   ├── common/
│   │   ├── common.mk       # Master Makefile (RISCV_PREFIX = riscv-none-elf-)
│   │   ├── crt0.S          # Startup code
│   │   └── neorv32.ld      # GCC linker script (ROM/RAM sections)
│   ├── example/            # 30+ example programs (blink, TWI, DMA, etc.)
│   ├── image_gen/          # Tool to convert ELF → bootloader-compatible .bin
│   ├── lib/
│   │   ├── include/        # Peripheral driver headers (gpio, uart, twi, dma, spi...)
│   │   └── source/         # Peripheral driver C implementations
│   ├── ocd-firmware/       # Debugger "park loop" firmware for OCD
│   └── openocd/            # OpenOCD configs for JTAG debug
└── docs/                   # User guide + datasheet (adoc → PDF)
```

## Key Technical Details

### XBUS → AXI4 Bridge
`rtl/system_integration/xbus2axi4_bridge.vhd` is critical — NeoRV32 uses XBUS (its internal bus) and this bridge converts to AXI4 for connecting to Xilinx IP like MIG, DMA, FIFOs. Our block design uses this bridge internally.

### Bootloader
- Pre-compiled image already baked into `neorv32_bootloader_image.vhd`
- Configured: UART 19200 baud, auto-boot 8s timeout, SPI flash enabled
- Can load from: Serial UART, SPI flash, TWI flash, SD card (FAT)
- Boots at 0xFFE00000 (ROM), loads application to 0x00000000 (IMEM)

### Toolchain Requirements
- Default prefix: `riscv-none-elf-` (not `riscv32-unknown-elf-`)
- ISA default: `rv32i_zicsr_zifencei` (our overlay uses RV32I + Zicond)
- Memory layout: ROM 0x00000000, RAM 0x80000000 (matching our config)
- `make clean bootloader` rebuilds + reinstalls the boot ROM image

### SES Integration
- SEGGER wiki: https://kb.segger.com/J-Link_NEORV32
- Tutorial: https://www.emb4fun.com/riscv/ses4rv/index.html
- JTAG speed must NOT exceed 1/5 of CPU clock (max ~20MHz for our 100MHz core)
- No RTT support (no system bus access from debugger)
- J-Link EDU Mini V2 fully compatible

## Our Overlay Matches
- IMEM: 32KB @ 0x00000000 ✅ matches default
- DMEM: 8KB @ 0x80000000 ✅ matches default ⚠️ BUT conflicts with DDR3 MIG!
  - Need to resolve: either move DMEM or use MIG at different base
- CPU clock: 100MHz → JTAG limit: ≤ 20MHz
- TWI, UART, GPIO all enabled and match the bootloader config
- NeoRV32's OCD must be enabled (it is) for J-Link debug

## Software Build Flow
```
Application .c/.s → GCC (riscv-none-elf-gcc) → .elf
  ├─→ image_gen → .bin (for bootloader UART upload)
  └─→ objcopy → .hex (for VHDL memory init)
Bootloader .c → GCC → image_gen → neorv32_bootloader_image.vhd
```

## What We Need
1. **RISC-V GCC** — either install standalone `riscv-none-elf-gcc` or use SES's `emBuild`
2. **Address map fix** — resolve DMEM vs DDR3 at 0x80000000
3. **SES project** — create/modify for our specific NeoRV32 config
4. **Test flow**: Load bitstream (Vivado) → SES connects via J-Link → debug firmware
