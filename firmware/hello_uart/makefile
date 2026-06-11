# ── hello_uart Makefile ───────────────────────────────────────
# NeoRV32 firmware project for the neorv_basic FPGA build.
#
# Hardware target:
#   FPGA:        Alchitry Pt V2 (XC7A100T)
#   Block design: neorv_basic
#   CPU clock:   160 MHz (MMCM from 100 MHz board osc)
#   ISA:         RV32IM + Zicond + Zicsr + Zifencei
#   IMEM:        128 KB @ 0x00000000
#   DMEM:        128 KB @ 0x80000000
#   UART0:       enabled, pins B15(TX)/F19(RX), actual baud ~30720
#   JTAG:        enabled via OCD, J-Link EDU Mini

# ── CPU Architecture ────────────────────────────────────────────
MARCH = rv32im_zicsr_zifencei_zicond

# ── RISC-V GCC Toolchain ────────────────────────────────────────
RISCV_PREFIX ?= riscv32-unknown-elf-

# ── Optimization ─────────────────────────────────────────────────
EFFORT = -Os

# ── Debug symbols ────────────────────────────────────────────────
USER_FLAGS += -ggdb -gdwarf-3

# ── Memory Sizes (must match FPGA build!) ────────────────────────
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=128k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=128k
USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=4k

# ── NEORV32 Root ─────────────────────────────────────────────────
NEORV32_HOME ?= ../../..

# ── Include NEORV32 build system ─────────────────────────────────
include $(NEORV32_HOME)/sw/common/common.mk
