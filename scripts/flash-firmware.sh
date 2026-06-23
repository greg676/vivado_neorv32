#!/bin/bash
# flash-firmware.sh — Flash NeoRV32 firmware via J-Link
# Usage: ./scripts/flash-firmware.sh [path/to/elf.bin]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default to debug_console firmware
FIRMWARE="${1:-$REPO_ROOT/firmware/debug_console/elf.bin}"

if [ ! -f "$FIRMWARE" ]; then
    echo "ERROR: Firmware not found: $FIRMWARE"
    echo "Usage: $0 [path/to/elf.bin]"
    exit 1
fi

echo "Flashing: $FIRMWARE"
echo "Waiting 3s for J-Link to stabilize..."
sleep 3

JLinkExe -device RISC-V -if JTAG -speed 1000 -autoconnect 1 \
    -JTAGConf "-1,-1" \
    -CommanderScript - <<EOF
r
halt
loadbin $FIRMWARE 0x00000000
wreg pc 0x00000000
go
exit
EOF

echo ""
echo "Firmware flashed successfully."
echo "Connect UART: screen /dev/ttyUSB0 19200"
