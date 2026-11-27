# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# Simulated LAT3 device → PulseView .sr (no hardware).
#   make            - self-test (LAT3 + UART/I2C + .sr; sigrok-cli if present)
#   make canned     - write uart/i2c/counter/walking .sr .lat3 .raw
#   make decode     - canned + sigrok-cli protocol decoders
#   make screenshot - PulseView under xvfb (needs pulseview + Xvfb)

PYTHON ?= python3
OUT    ?= canned

.PHONY: all selftest canned decode screenshot clean

all: selftest canned

selftest:
	$(PYTHON) eval_pulseview.py --self-test

canned:
	$(PYTHON) eval_pulseview.py --pattern all --out-dir $(OUT)

decode: canned
	$(PYTHON) eval_pulseview.py --pattern all --out-dir $(OUT) --decode

screenshot: canned
	$(PYTHON) eval_pulseview.py --pattern uart --out-dir $(OUT) \
		--screenshot $(OUT)/pulseview-uart.png
	$(PYTHON) eval_pulseview.py --pattern i2c --out-dir $(OUT) \
		--screenshot $(OUT)/pulseview-i2c.png

clean:
	rm -rf $(OUT) __pycache__
