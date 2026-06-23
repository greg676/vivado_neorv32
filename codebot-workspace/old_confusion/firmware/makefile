# CodecBot Debug CLI - NeoRV32 application makefile

MARCH = rv32i_zicsr_zifencei_zicond
EFFORT = -Os
USER_FLAGS += -ggdb -gdwarf-3
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=128k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=128k
USER_FLAGS += -nostdlib
USER_FLAGS += -L/usr/lib/picolibc/riscv64-unknown-elf/lib/rv32i/ilp32
USER_FLAGS += -L/usr/lib/gcc/riscv64-unknown-elf/13.2.0/rv32i/ilp32

APP_SRC += $(wildcard ./*.c)
APP_INC += -I/usr/lib/picolibc/riscv64-unknown-elf/include

NEORV32_HOME ?= /home/greg-jack/vivado_projects/Neorv32_demos/NeoRV32_AuV1/neorv32
include $(NEORV32_HOME)/sw/common/common.mk
