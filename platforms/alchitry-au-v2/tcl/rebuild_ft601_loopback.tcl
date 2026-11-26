# Recreates FT601 245 loopback for Alchitry Au (xc7a35t) + Ft+ V2.
# No NeoRV32. SRAM bitstream only (do not --write-flash).
#
# From platforms/alchitry-au-v2:
#   vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl
#
# Optional:
#   set ft601_mode "LOOPBACK"   ;# or "TX_COUNTER"
#   set skip_impl  1

if {![info exists ft601_pinout]} {
    set ft601_pinout "v2"
}
if {![info exists ft601_mode]} {
    set ft601_mode "LOOPBACK"
}

set project_name "ft601_loopback_au"
set project_dir  "./vivado_project_ft601"
set part         "xc7a35ticsg324-1"

puts "FT601 Au loopback project"
puts "  pinout : $ft601_pinout (published Au Ft+ V2)"
puts "  mode   : $ft601_mode"
puts "  part   : $part"

create_project -force $project_name $project_dir -part $part

add_files -fileset sources_1 [list \
    ./rtl/ft601/ft601_fwft_fifo.v \
    ./rtl/ft601/ft601_sync_fifo.v \
    ./rtl/ft601/ft601_reset.v \
    ./rtl/ft601/ft601_loopback_core.v \
    ./rtl/ft601/ft601_loopback_top.v \
]

add_files -fileset constrs_1 [list \
    ./constraints/au_ft601_pins_v2.xdc \
    ./constraints/au_ft601_loopback.xdc \
    ./constraints/au_ft601_impl.xdc \
]
set_property used_in_synthesis false [get_files -quiet *au_ft601_impl.xdc]

set_property top ft601_loopback_top [current_fileset]
set_property generic [list MODE=$ft601_mode] [get_filesets sources_1]

puts "Project created at $project_dir"
puts "RAM program (not flash): openFPGALoader --fpga-part xc7a35t <bit>"

if {![info exists skip_impl] || !$skip_impl} {
    source [file join [file dirname [info script]] run_impl.tcl]
}
