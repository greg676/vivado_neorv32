# 245 FT601 loopback sim (Icarus). No Vivado, no flash.
#   make -C platforms/alchitry-platinum-v2/sim/ft601

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3

RTL := \
	../../rtl/ft601/ft601_fwft_fifo.v \
	../../rtl/ft601/ft601_sync_fifo.v \
	../../rtl/ft601/ft601_loopback_core.v \
	../../rtl/ft601/ft601_reset.v

TB := \
	ft601_phy_245.v \
	ft601_245_monitor.v \
	tb_ft601_loopback.v

IVFLAGS := -g2005-sv -DSIMULATION
VVPFLAGS ?=

VECTORS := \
	vectors/counter.bin vectors/counter.hex \
	vectors/walking.bin vectors/walking.hex \
	vectors/xor.bin vectors/xor.hex

.PHONY: all vectors run vcd clean

all: run

vectors: $(VECTORS)

$(VECTORS): vectors/gen_vectors.py
	$(PYTHON) vectors/gen_vectors.py

tb_ft601_loopback.vvp: $(RTL) $(TB) $(VECTORS)
	$(IVERILOG) $(IVFLAGS) -o $@ $(RTL) $(TB)

run: tb_ft601_loopback.vvp
	$(VVP) $(VVPFLAGS) $<

vcd: tb_ft601_loopback.vvp
	$(VVP) $(VVPFLAGS) $< +vcd

clean:
	rm -f tb_ft601_loopback.vvp tb_ft601_loopback.vcd vectors/sim_echo.bin
