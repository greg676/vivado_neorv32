# Recreates FT601 245 tests for Alchitry Au (xc7a35t) + Ft+ V2.
# No NeoRV32. SRAM bitstream only (do not --write-flash).
#
# From platforms/alchitry-au-v2:
#   vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl
#
# Optional:
#   set ft601_mode "LOOPBACK"   ;# or "TX_ONLY" / "RX_ONLY"
#   set skip_impl  1
#   set part "xc7a35tftg256-1"  ;# gj-007: CSG324 not installed
#
if {![info exists ft601_pinout]} {
    set ft601_pinout "v2"
}
if {![info exists ft601_mode]} {
    set ft601_mode "LOOPBACK"
}

set project_name "ft601_loopback_au"
set project_dir  "./vivado_project_ft601"
# Published Au V2 is CSG324; gj-007 Vivado has FTG256. Same V2 XDC balls
# are user I/O on FTG256 (P-side MRCC D4 for ft_clk).
if {![info exists part]} {
    set part "xc7a35tftg256-1"
}

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
set_property generic [list [format {MODE="%s"} $ft601_mode]] [get_filesets sources_1]

puts "Project created at $project_dir"
puts "RAM program (not flash): openFPGALoader --fpga-part xc7a35tftg256 --write-sram <bit>"

if {![info exists skip_impl] || !$skip_impl} {
    source [file join [file dirname [info script]] run_impl.tcl]
}
