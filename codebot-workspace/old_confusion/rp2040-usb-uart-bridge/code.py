# code.py — RP2040 Zero USB-UART Passthrough Bridge
#
# Routes USB CDC serial ↔ hardware UART for the NeoRV32 FPGA console.
#
# Wiring (RP2040 Zero → FPGA Pt V2 Br breakout):
#   RP2040 GP0 (UART0 TX) → FPGA UART RX
#   RP2040 GP1 (UART0 RX) → FPGA UART TX
#   RP2040 GND            → FPGA GND

import board
import busio
import usb_cdc
import time

BAUD = 115200

uart = busio.UART(
    tx=board.GP0,
    rx=board.GP1,
    baudrate=BAUD,
    bits=8,
    parity=None,
    stop=1,
    timeout=0,
)

# Blink neoPixel green on boot if available
try:
    import neopixel
    np = neopixel.NeoPixel(board.GP16, 1)
    np[0] = (0, 255, 0)  # green = ready
except:
    np = None

usb = usb_cdc.data

while True:
    if uart.in_waiting:
        data = uart.read(uart.in_waiting)
        if data:
            usb.write(data)
    if usb.in_waiting:
        data = usb.read(usb.in_waiting)
        if data:
            uart.write(data)
    time.sleep(0.0001)
