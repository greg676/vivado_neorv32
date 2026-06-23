# boot.py — Enable dual CDC serial (console + data)
# Required for usb_cdc.data to be available in code.py
import usb_cdc
usb_cdc.enable(console=True, data=True)
