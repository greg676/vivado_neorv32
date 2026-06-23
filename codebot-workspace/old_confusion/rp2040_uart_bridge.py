# main.py — RP2040 Zero USB-UART Passthrough Bridge (MicroPython)
#
# Wiring: GP0=TX → FPGA UART RX, GP1=RX → FPGA UART TX
# Baud: 19200 (matches NeoRV32 bootloader default)
#
# IMPORTANT: This works with terminals that set VMIN=0, VTIME>0 
# (e.g. `stty min 0 time 1`), making stdin.read() non-blocking.

from machine import UART, Pin
import sys
import time

BAUD = 19200
uart = UART(0, baudrate=BAUD, tx=Pin(0), rx=Pin(1), bits=8, parity=None, stop=1)

print(f"UART bridge: {BAUD} 8N1, GP0→FPGA_RX, GP1→FPGA_TX")

while True:
    # FPGA → PC
    n = uart.any()
    if n:
        sys.stdout.buffer.write(uart.read(n))

    # PC → FPGA (non-blocking because terminal has VMIN=0)
    try:
        c = sys.stdin.buffer.read(1)
        if c:
            uart.write(c)
    except:
        pass
