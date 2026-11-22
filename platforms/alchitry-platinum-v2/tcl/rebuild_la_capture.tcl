# ── rebuild_la_capture.tcl ──────────────────────────────────────
# Recreates a dedicated 8-channel LA capture Vivado project (no NeoRV32).
#
# From platforms/alchitry-platinum-v2:
#   vivado -mode batch -source tcl/rebuild_la_capture.tcl
#
# Optional (before sourcing, or edit defaults below):
#   set ft601_pinout   "pt_alpha"   ;# first-batch Pt (default)
#   set ft601_pinout   "v2"         ;# production Pt V2
#   set la_sample_mhz  100          ;# or 200 (DDR @ 100 MHz ft_clk)
#   set la_source      0            ;# 0=counter 1=walking 2=live
#   set la_buf_depth   4096         ;# circular BRAM entries (power of two)
#   set la_post        2048         ;# default post-trigger samples
#   set la_trig_ch     0            ;# trigger channel 0-7
#   set la_trig_edge   0            ;# 0=rise 1=fall 2=both 3=immediate
#   set skip_impl      1            ;# project only, no bitstream
#   set impl_jobs      8

if {![info exists ft601_pinout]} {
    set ft601_pinout "pt_alpha"
}
if {![info exists la_sample_mhz]} {
    set la_sample_mhz 100
}
if {![info exists la_source]} {
    set la_source 0
}
if {![info exists la_buf_depth]} {
    set la_buf_depth 4096
}
if {![info exists la_post]} {
    set la_post 2048
}
if {![info exists la_trig_ch]} {
    set la_trig_ch 0
}
if {![info exists la_trig_edge]} {
    set la_trig_edge 0
}

if {$la_sample_mhz != 100 && $la_sample_mhz != 200} {
    error "la_sample_mhz must be 100 or 200 (got $la_sample_mhz)"
}

set project_name "la_capture"
set project_dir  "./vivado_project_la_capture"
set part         "xc7a100tfgg484-2"

puts "LA capture project"
puts "  pinout     : $ft601_pinout"
puts "  sample_mhz : $la_sample_mhz"
puts "  source     : $la_source  (0=counter 1=walking 2=live)"
puts "  buf_depth  : $la_buf_depth  BRAM entries (not DDR3)"
puts "  post       : $la_post  default post-trigger samples"
puts "  trig_ch    : $la_trig_ch"
puts "  trig_edge  : $la_trig_edge  (0=rise 1=fall 2=both 3=imm)"
puts "  part       : $part"

create_project -force $project_name $project_dir -part $part

add_files -fileset sources_1 [list \
    ./rtl/ft601/ft601_fwft_fifo.v \
    ./rtl/ft601/ft601_sync_fifo.v \
    ./rtl/ft601/ft601_reset.v \
    ./rtl/la/la_iddr1.v \
    ./rtl/la/la_sampler.v \
    ./rtl/la/la_pattern.v \
    ./rtl/la/la_packer.v \
    ./rtl/la/la_trig.v \
    ./rtl/la/la_circ_bram.v \
    ./rtl/la/la_capture_ctrl.v \
    ./rtl/la/la_ddr3_stub.v \
    ./rtl/la/la_capture_core.v \
    ./rtl/la/la_capture_top.v \
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
    ./constraints/ptv2_ft601_impl.xdc \
    ./constraints/ptv2_la_capture.xdc \
]
set_property used_in_synthesis false [get_files -quiet *ptv2_ft601_impl.xdc]

set_property top la_capture_top [current_fileset]
set_property generic [list \
    SAMPLE_MHZ=$la_sample_mhz \
    DEFAULT_SOURCE=$la_source \
    BUF_DEPTH=$la_buf_depth \
    DEFAULT_POST=$la_post \
    DEFAULT_CH=$la_trig_ch \
    DEFAULT_EDGE=$la_trig_edge \
] [get_filesets sources_1]

puts "Project created at $project_dir"
puts "GUI: File → Open Project → $project_dir/la_capture.xpr"
puts "RAM program (not flash): vivado -mode batch -source tcl/program_ram.tcl -tclargs \\"
puts "  $project_dir/la_capture.runs/impl_1/la_capture_top.bit"

if {![info exists skip_impl] || !$skip_impl} {
    source [file join [file dirname [info script]] run_impl.tcl]
}
