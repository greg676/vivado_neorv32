MARCH = rv32im_zicsr_zifencei_zicond
RISCV_PREFIX = ./tools/riscv32-unknown-elf-
EFFORT = -Os
USER_FLAGS += -ggdb -gdwarf-3
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=128k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=128k
USER_FLAGS += -Wl,--defsym,__neorv32_heap_size=4k
NEORV32_HOME = /home/greg-jack/vivado_projects/neorv32-main
include $(NEORV32_HOME)/sw/common/common.mk
