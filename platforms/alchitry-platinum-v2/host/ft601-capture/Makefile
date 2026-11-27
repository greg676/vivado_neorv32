# FT601 LA capture dump.
#   make            - packer self-test (no SDK)
#   make d3xx       - hardware binary against FTDI D3XX
#
# Point D3XX_DIR at the unpacked linux SDK (contains ftd3xx.h and libftd3xx.so).

CC       ?= gcc
CFLAGS   ?= -O2 -Wall -Wextra -std=c11
D3XX_DIR ?= /opt/ftdi/d3xx

.PHONY: all d3xx clean selftest

all: ft601_capture_selftest

ft601_capture_selftest: ft601_capture.c
	$(CC) $(CFLAGS) -DFT601_NO_D3XX -o $@ ft601_capture.c

d3xx: ft601_capture

ft601_capture: ft601_capture.c
	$(CC) $(CFLAGS) -I$(D3XX_DIR) -o $@ ft601_capture.c \
		-L$(D3XX_DIR) -lftd3xx -lpthread -ldl

selftest: ft601_capture_selftest
	./ft601_capture_selftest --self-test
	python3 ft601_capture.py --self-test

clean:
	rm -f ft601_capture ft601_capture_selftest
