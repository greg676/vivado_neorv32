# Icarus self-check for the Au LA sample packer. No FT601 / USB.
IVERILOG ?= iverilog
VVP      ?= vvp
RTL      := ../../rtl/la/la_pattern.v

.PHONY: all test clean

all: test

test: tb_la_pattern.vvp
	$(VVP) $<

tb_la_pattern.vvp: tb_la_pattern.v $(RTL)
	$(IVERILOG) -g2012 -o $@ tb_la_pattern.v $(RTL)

clean:
	rm -f *.vvp
