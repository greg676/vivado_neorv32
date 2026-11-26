# Icarus self-check for the Au LA packer + dual 4 KiB BRAM. No FT601 / USB.
IVERILOG ?= iverilog
VVP      ?= vvp
PAT_RTL  := ../../rtl/la/la_pattern.v
PP_RTL   := ../../rtl/la/la_pingpong_bram.v

.PHONY: all test clean

all: test

test: tb_la_pattern.vvp tb_la_pingpong.vvp
	$(VVP) tb_la_pattern.vvp
	$(VVP) tb_la_pingpong.vvp

tb_la_pattern.vvp: tb_la_pattern.v $(PAT_RTL)
	$(IVERILOG) -g2012 -o $@ tb_la_pattern.v $(PAT_RTL)

tb_la_pingpong.vvp: tb_la_pingpong.v $(PP_RTL)
	$(IVERILOG) -g2012 -o $@ tb_la_pingpong.v $(PP_RTL)

clean:
	rm -f *.vvp
