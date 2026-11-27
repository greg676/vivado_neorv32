# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# Icarus: AXI DDR buffer + Pt capture core. PHY is the Au 4 KiB core.
# No Vivado / MIG / QSPI.
IVERILOG ?= iverilog
VVP      ?= vvp

AU_LA  := ../../../alchitry-au-v2/rtl/la
AU_PHY := ../../../alchitry-au-v2/rtl/ft601
PT_LA  := ../../rtl/la

PAT := $(AU_LA)/la_pattern.v
PP  := $(AU_LA)/la_pingpong_bram.v
PHY := $(AU_PHY)/ft601_sync_fifo.v
BUF := $(PT_LA)/la_ddr3_axi_buf.v $(PT_LA)/la_dc_fwft.v
CORE := $(PT_LA)/pvla_mig7_capture_core.v
MEM := axi_sram_slave.v

.PHONY: all test clean

all: test

test: tb_la_ddr3_axi_buf.vvp tb_pvla_mig7_stream.vvp
	$(VVP) tb_la_ddr3_axi_buf.vvp
	$(VVP) tb_pvla_mig7_stream.vvp

tb_la_ddr3_axi_buf.vvp: tb_la_ddr3_axi_buf.v $(PAT) $(BUF) $(MEM)
	$(IVERILOG) -g2012 -o $@ tb_la_ddr3_axi_buf.v $(PAT) $(BUF) $(MEM)

tb_pvla_mig7_stream.vvp: tb_pvla_mig7_stream.v $(PAT) $(PP) $(PHY) $(BUF) $(CORE) $(MEM)
	$(IVERILOG) -g2012 -o $@ tb_pvla_mig7_stream.v $(PAT) $(PP) $(PHY) $(BUF) $(CORE) $(MEM)

clean:
	rm -f *.vvp
