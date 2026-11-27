# Program Artix-7 SRAM from a .bit. Never SPI flash / QSPI.
#
#   vivado -mode batch -source tcl/program_ram.tcl -tclargs \
#     bitstreams/ft601_loopback_top_v2.bit

if {$argc < 1} {
    puts "usage: vivado -mode batch -source tcl/program_ram.tcl -tclargs <file.bit>"
    puts "RAM only — will not write SPI flash / .mcs."
    exit 1
}

set bitfile [file normalize [lindex $argv 0]]
if {![file exists $bitfile]} {
    puts "error: bitstream not found: $bitfile"
    exit 1
}

puts "Programming FPGA RAM (not flash)"
puts "  bit : $bitfile"

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
if {$device eq ""} {
    puts "error: no hw_device (board disconnected?)"
    close_hw_manager
    exit 1
}

current_hw_device $device
set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device
refresh_hw_device $device

puts "PROGRAM_OK  device=$device  (RAM, not flash)"
close_hw_manager
