# RTL loopback sim (no Vivado required).
# Usage: make -C platforms/alchitry-platinum-v2/sim/ft601

IVERILOG ?= iverilog
VVP      ?= vvp

RTL := \
	../../rtl/ft601/ft601_fwft_fifo.v \
	../../rtl/ft601/ft601_sync_fifo.v \
	../../rtl/ft601/ft601_loopback_core.v

TB := \
	ft601_bus_model.v \
	tb_ft601_loopback.v

.PHONY: all run clean

all: run

tb_ft601_loopback.vvp: $(RTL) $(TB)
	$(IVERILOG) -g2005-sv -o $@ $(RTL) $(TB)

run: tb_ft601_loopback.vvp
	$(VVP) $<

clean:
	rm -f tb_ft601_loopback.vvp
