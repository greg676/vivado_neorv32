# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# FT601 LA triggered capture dump.
#   make            - packer + LAT3 header self-test (no USB)
#   make hw         - hardware binary against libusb-1.0 (preferred)
#   make d3xx       - hardware binary against FTDI D3XX (optional)
#
# D3XX_DIR must contain ftd3xx.h and libftd3xx.so (unpack the Linux SDK).

CC       ?= gcc
CFLAGS   ?= -O2 -Wall -Wextra -std=c11
D3XX_DIR ?= /opt/ftdi/d3xx
USB_DIR  := ../common
USB_CFLAGS := $(shell pkg-config --cflags libusb-1.0 2>/dev/null)
USB_LIBS   := $(shell pkg-config --libs libusb-1.0 2>/dev/null)
ifeq ($(USB_LIBS),)
USB_LIBS := -lusb-1.0
endif

.PHONY: all hw d3xx clean selftest

all: ft601_capture_selftest

ft601_capture_selftest: ft601_capture.c
	$(CC) $(CFLAGS) -DFT601_NO_HW -o $@ ft601_capture.c

hw: ft601_capture

ft601_capture: ft601_capture.c $(USB_DIR)/ft601_usb.c $(USB_DIR)/ft601_usb.h
	$(CC) $(CFLAGS) $(USB_CFLAGS) -I$(USB_DIR) -o $@ \
		ft601_capture.c $(USB_DIR)/ft601_usb.c $(USB_LIBS)

d3xx: ft601_capture_d3xx

ft601_capture_d3xx: ft601_capture.c $(USB_DIR)/ft601_usb.c $(USB_DIR)/ft601_usb.h
	@test -f $(D3XX_DIR)/ftd3xx.h || { \
	  echo "D3XX headers missing. Unpack the FTDI Linux D3XX SDK to $(D3XX_DIR)"; \
	  echo "(need ftd3xx.h and libftd3xx.so — the .so alone is not enough)."; \
	  exit 1; }
	$(CC) $(CFLAGS) -DFT601_USE_D3XX -I$(USB_DIR) -I$(D3XX_DIR) -o $@ \
		ft601_capture.c $(USB_DIR)/ft601_usb.c \
		-L$(D3XX_DIR) -lftd3xx -lpthread -ldl

selftest: ft601_capture_selftest
	./ft601_capture_selftest --self-test
	python3 ft601_capture.py --self-test

clean:
	rm -f ft601_capture ft601_capture_selftest ft601_capture_d3xx
