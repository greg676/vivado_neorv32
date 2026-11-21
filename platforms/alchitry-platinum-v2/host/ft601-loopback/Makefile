# FT601 loopback host tool.
#   make            - pattern self-test (no SDK)
#   make d3xx       - hardware binary against FTDI D3XX
#
# Point D3XX_DIR at the unpacked linux SDK (contains ftd3xx.h and libftd3xx.so).

CC       ?= gcc
CFLAGS   ?= -O2 -Wall -Wextra -std=c11
D3XX_DIR ?= /opt/ftdi/d3xx

.PHONY: all d3xx clean selftest

all: ft601_loopback_selftest

ft601_loopback_selftest: ft601_loopback.c
	$(CC) $(CFLAGS) -DFT601_NO_D3XX -o $@ ft601_loopback.c

d3xx: ft601_loopback

ft601_loopback: ft601_loopback.c
	$(CC) $(CFLAGS) -I$(D3XX_DIR) -o $@ ft601_loopback.c \
		-L$(D3XX_DIR) -lftd3xx -lpthread -ldl

selftest: ft601_loopback_selftest
	./ft601_loopback_selftest --self-test

clean:
	rm -f ft601_loopback ft601_loopback_selftest
