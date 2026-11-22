# Program the Artix-7 from a .bit into volatile SRAM. Never SPI flash.
#
# Board must be connected. This agent does not run this file.
#
# From platforms/alchitry-platinum-v2:
#   vivado -mode batch -source tcl/program_ram.tcl -tclargs \
#     bitstreams/ft601_loopback_top_pt_alpha.bit
#
# Or pass the impl_1 path:
#   vivado_project_ft601/ft601_loopback.runs/impl_1/ft601_loopback_top.bit

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
# Explicitly do not touch the SPI flash programmer.
program_hw_devices $device
refresh_hw_device $device

puts "PROGRAM_OK  device=$device  (RAM, not flash)"
close_hw_manager
