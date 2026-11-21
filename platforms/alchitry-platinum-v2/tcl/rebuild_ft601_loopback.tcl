# ── rebuild_ft601_loopback.tcl ──────────────────────────────────
# Recreates a dedicated FT601 loopback Vivado project (no NeoRV32).
#
# From platforms/alchitry-platinum-v2:
#   vivado -mode batch -source tcl/rebuild_ft601_loopback.tcl
#
# Optional (before sourcing, or edit defaults below):
#   set ft601_pinout "pt_alpha"   ;# first-batch Pt (default, matches repo notes)
#   set ft601_pinout "v2"         ;# production Pt V2
#   set ft601_mode   "LOOPBACK"   ;# or "TX_COUNTER"

if {![info exists ft601_pinout]} {
    set ft601_pinout "pt_alpha"
}
if {![info exists ft601_mode]} {
    set ft601_mode "LOOPBACK"
}

set project_name "ft601_loopback"
set project_dir  "./vivado_project_ft601"
set part         "xc7a100tfgg484-2"

puts "FT601 loopback project"
puts "  pinout : $ft601_pinout"
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

if {$ft601_pinout eq "v2"} {
    set pin_xdc ./constraints/ptv2_ft601_pins_v2.xdc
} else {
    set pin_xdc ./constraints/ptv2_ft601_pins_pt_alpha.xdc
}

# Pin-map XDC first so ft_clk exists before common timing constraints.
add_files -fileset constrs_1 [list \
    $pin_xdc \
    ./constraints/ptv2_ft601_loopback.xdc \
]

set_property top ft601_loopback_top [current_fileset]
set_property generic [list MODE=$ft601_mode] [get_filesets sources_1]

puts "Project created at $project_dir"
puts "Next: open in Vivado and Generate Bitstream, or:"
puts "  launch_runs impl_1 -to_step write_bitstream -jobs 4"
puts "  wait_on_run impl_1"
