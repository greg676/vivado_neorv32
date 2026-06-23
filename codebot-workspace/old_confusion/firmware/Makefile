# Makefile for codecbot_debug_cli firmware

PREFIX   ?= riscv-none-elf-
CC       := $(PREFIX)gcc
OBJCOPY  := $(PREFIX)objcopy
SIZE     := $(PREFIX)size

NEORV32_HOME := /home/greg-jack/vivado_projects/Neorv32_demos/NeoRV32_AuV1/neorv32

BUILDDIR := build

CFLAGS   := -march=rv32i_zicsr_zifencei_zicond -mabi=ilp32 -O2 -g -Wall -Wextra \
            -ffunction-sections -fdata-sections -fno-common -fno-builtin-printf \
            -I. \
            -I$(NEORV32_HOME)/sw/lib/include \
            -I$(NEORV32_HOME)/sw/common \
            -I/usr/lib/picolibc/riscv64-unknown-elf/include \
            -DNEORV32_UART0_EN -DNEORV32_TWI_EN -DNEORV32_SPI_EN \
            -DNEORV32_GPIO_EN -DNEORV32_PWM_EN

LDFLAGS  := -march=rv32i_zicsr_zifencei_zicond -mabi=ilp32 \
            -T $(NEORV32_HOME)/sw/common/neorv32.ld \
            -nostartfiles -nostdlib -Wl,--gc-sections -Wl,-static \
            -L/usr/lib/picolibc/riscv64-unknown-elf/lib/rv32i/ilp32 \
            -L/usr/lib/gcc/riscv64-unknown-elf/13.2.0/rv32i/ilp32 \
            -Wl,--defsym,__neorv32_rom_size=128k \
            -Wl,--defsym,__neorv32_ram_size=128k \
            -lc -lgcc

all: $(BUILDDIR)/debug_cli.elf $(BUILDDIR)/debug_cli.bin

$(BUILDDIR)/debug_cli.elf: $(BUILDDIR)/debug_cli.o $(BUILDDIR)/crt0.o | $(BUILDDIR)
	@echo "Linking $@"
	$(CC) $(BUILDDIR)/debug_cli.o $(BUILDDIR)/crt0.o $(LDFLAGS) -o $@
	$(SIZE) $@

$(BUILDDIR)/debug_cli.o: debug_cli.c | $(BUILDDIR)
	@echo "Compiling $<"
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/crt0.o: $(NEORV32_HOME)/sw/common/crt0.S | $(BUILDDIR)
	@echo "Assembling crt0.S"
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILDDIR)/debug_cli.bin: $(BUILDDIR)/debug_cli.elf | $(BUILDDIR)
	@echo "Creating binary $@"
	$(OBJCOPY) -O binary $< $@

clean:
	rm -rf $(BUILDDIR)

$(BUILDDIR):
	mkdir -p $@

.PHONY: all clean
