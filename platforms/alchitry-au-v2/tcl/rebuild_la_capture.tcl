# Recreates the Au V2 LA capture bitstream (xc7a35t + Ft+ V2).
# Same PR #18 PHY as loopback. No NeoRV32. SRAM only (do not --write-flash).
#
# From platforms/alchitry-au-v2:
#   vivado -mode batch -source tcl/rebuild_la_capture.tcl
#
# Optional:
#   set skip_impl  1
#   set part "xc7a35tftg256-1"
#
if {![info exists ft601_pinout]} {
    set ft601_pinout "v2"
}
# Not TX_ONLY/RX_ONLY: run_impl names the bit ${top}_${pinout}.bit
if {![info exists ft601_mode]} {
    set ft601_mode "CAPTURE"
}

set project_name "la_capture_au"
set project_dir  "./vivado_project_la_capture"
if {![info exists part]} {
    set part "xc7a35tftg256-1"
}

puts "FT601 Au LA capture project"
puts "  pinout : $ft601_pinout (published Au Ft+ V2)"
puts "  mode   : $ft601_mode"
puts "  part   : $part"

create_project -force $project_name $project_dir -part $part

add_files -fileset sources_1 [list \
    ./rtl/ft601/ft601_sync_fifo.v \
    ./rtl/ft601/ft601_reset.v \
    ./rtl/la/la_pattern.v \
    ./rtl/la/la_pingpong_bram.v \
    ./rtl/la/la_capture_core.v \
    ./rtl/la/la_capture_top.v \
]

add_files -fileset constrs_1 [list \
    ./constraints/au_ft601_pins_v2.xdc \
    ./constraints/au_ft601_loopback.xdc \
    ./constraints/au_ft601_impl.xdc \
]
set_property used_in_synthesis false [get_files -quiet *au_ft601_impl.xdc]

set_property top la_capture_top [current_fileset]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraTimingOpt [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

puts "Project created at $project_dir"
puts "RAM program (not flash): openFPGALoader --fpga-part xc7a35tftg256 --write-sram <bit>"

if {![info exists skip_impl] || !$skip_impl} {
    source [file join [file dirname [info script]] run_impl.tcl]
}
