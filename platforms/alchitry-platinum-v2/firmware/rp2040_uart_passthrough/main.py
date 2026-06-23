# RP2040 Zero USB-UART Passthrough
# GP0 = UART0 TX → FPGA RX (pin F19)
# GP1 = UART0 RX ← FPGA TX (pin B15)
# 19200 baud, 8N1
#
# Auto-starts on boot. Upload as main.py via Thonny.
# To recover REPL: Bootsel on power-up, re-flash MicroPython.
# UF2: https://micropython.org/download/WAVESHARE_RP2040_ZERO/

from machine import UART, Pin
import sys, select, time

uart0 = UART(0, 19200, tx=Pin(0), rx=Pin(1))

# Give host time to connect
time.sleep_ms(500)

# Send a marker so we know passthrough is alive
uart0.write(b'')  # don't send to FPGA, just init

running = True
while running:
    try:
        # FPGA → Host
        if uart0.any():
            data = uart0.read()
            if data:
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()

        # Host → FPGA
        if select.select([sys.stdin], [], [], 0)[0]:
            ch = sys.stdin.buffer.read(1)
            if ch:
                uart0.write(ch)
    except:
        pass