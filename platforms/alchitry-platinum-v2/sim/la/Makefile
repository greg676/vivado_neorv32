# LA capture sim (no Vivado required).
# Usage: make -C platforms/alchitry-platinum-v2/sim/la

IVERILOG ?= iverilog
VVP      ?= vvp

LA_RTL := \
	../../rtl/la/la_iddr1.v \
	../../rtl/la/la_sampler.v \
	../../rtl/la/la_pattern.v \
	../../rtl/la/la_packer.v \
	../../rtl/la/la_trig.v \
	../../rtl/la/la_circ_bram.v \
	../../rtl/la/la_capture_ctrl.v \
	../../rtl/la/la_ddr3_stub.v \
	../../rtl/la/la_capture_core.v

FT_RTL := \
	../../rtl/ft601/ft601_fwft_fifo.v \
	../../rtl/ft601/ft601_sync_fifo.v

BUS := ../ft601/ft601_bus_model.v

IVFLAGS := -g2005-sv -DSIMULATION

.PHONY: all packer trig capture capture200 walking trigger run clean

all: run

run: packer trig capture capture200 walking trigger

tb_la_packer.vvp: ../../rtl/la/la_pattern.v ../../rtl/la/la_packer.v tb_la_packer.v
	$(IVERILOG) $(IVFLAGS) -o $@ \
		../../rtl/la/la_pattern.v ../../rtl/la/la_packer.v tb_la_packer.v

tb_la_trig.vvp: ../../rtl/la/la_trig.v tb_la_trig.v
	$(IVERILOG) $(IVFLAGS) -o $@ ../../rtl/la/la_trig.v tb_la_trig.v

tb_la_capture_100.vvp: $(LA_RTL) $(FT_RTL) $(BUS) tb_la_capture.v
	$(IVERILOG) $(IVFLAGS) -DSAMPLE_MHZ=100 -DSRC_SEL=0 -o $@ \
		$(LA_RTL) $(FT_RTL) $(BUS) tb_la_capture.v

tb_la_capture_200.vvp: $(LA_RTL) $(FT_RTL) $(BUS) tb_la_capture.v
	$(IVERILOG) $(IVFLAGS) -DSAMPLE_MHZ=200 -DSRC_SEL=0 -o $@ \
		$(LA_RTL) $(FT_RTL) $(BUS) tb_la_capture.v

tb_la_capture_walk.vvp: $(LA_RTL) $(FT_RTL) $(BUS) tb_la_capture.v
	$(IVERILOG) $(IVFLAGS) -DSAMPLE_MHZ=100 -DSRC_SEL=1 -o $@ \
		$(LA_RTL) $(FT_RTL) $(BUS) tb_la_capture.v

tb_la_trigger.vvp: $(LA_RTL) $(FT_RTL) $(BUS) tb_la_trigger.v
	$(IVERILOG) $(IVFLAGS) -o $@ $(LA_RTL) $(FT_RTL) $(BUS) tb_la_trigger.v

packer: tb_la_packer.vvp
	$(VVP) $<

trig: tb_la_trig.vvp
	$(VVP) $<

capture: tb_la_capture_100.vvp
	$(VVP) $<

capture200: tb_la_capture_200.vvp
	$(VVP) $<

walking: tb_la_capture_walk.vvp
	$(VVP) $<

trigger: tb_la_trigger.vvp
	$(VVP) $<

clean:
	rm -f *.vvp
