# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# Icarus self-check for the Au LA packer + dual 4 KiB FWFT BRAM. No USB.
IVERILOG ?= iverilog
VVP      ?= vvp
PAT_RTL  := ../../rtl/la/la_pattern.v
PP_RTL   := ../../rtl/la/la_pingpong_bram.v
CAP_RTL  := ../../rtl/la/la_capture_core.v ../../rtl/ft601/ft601_sync_fifo.v

.PHONY: all test clean

all: test

test: tb_la_pattern.vvp tb_la_pingpong.vvp tb_la_pingpong_stream.vvp tb_la_pingpong_rate.vvp tb_la_capture_wr.vvp tb_la_capture_data.vvp
	$(VVP) tb_la_pattern.vvp
	$(VVP) tb_la_pingpong.vvp
	$(VVP) tb_la_pingpong_stream.vvp
	$(VVP) tb_la_pingpong_rate.vvp
	$(VVP) tb_la_capture_wr.vvp
	$(VVP) tb_la_capture_data.vvp

IVFLAGS  := -g2012 -DICARUS

tb_la_pattern.vvp: tb_la_pattern.v $(PAT_RTL)
	$(IVERILOG) $(IVFLAGS) -o $@ tb_la_pattern.v $(PAT_RTL)

tb_la_pingpong.vvp: tb_la_pingpong.v $(PP_RTL)
	$(IVERILOG) $(IVFLAGS) -o $@ tb_la_pingpong.v $(PP_RTL)

tb_la_pingpong_stream.vvp: tb_la_pingpong_stream.v $(PAT_RTL) $(PP_RTL)
	$(IVERILOG) $(IVFLAGS) -o $@ tb_la_pingpong_stream.v $(PAT_RTL) $(PP_RTL)

tb_la_pingpong_rate.vvp: tb_la_pingpong_rate.v $(PAT_RTL) $(PP_RTL)
	$(IVERILOG) $(IVFLAGS) -o $@ tb_la_pingpong_rate.v $(PAT_RTL) $(PP_RTL)

tb_la_capture_wr.vvp: tb_la_capture_wr.v $(PAT_RTL) $(PP_RTL) $(CAP_RTL)
	$(IVERILOG) $(IVFLAGS) -o $@ tb_la_capture_wr.v $(PAT_RTL) $(PP_RTL) $(CAP_RTL)

tb_la_capture_data.vvp: tb_la_capture_data.v $(PAT_RTL) $(PP_RTL) $(CAP_RTL)
	$(IVERILOG) $(IVFLAGS) -o $@ tb_la_capture_data.v $(PAT_RTL) $(PP_RTL) $(CAP_RTL)

clean:
	rm -f *.vvp
