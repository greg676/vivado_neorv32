# SPDX-FileCopyrightText: 2026 Greg Jackson
# SPDX-License-Identifier: MIT
# ── pvla_bd_example.tcl (Au V2) ─────────────────────────────────
# Example Block Design: one PVLA on the proven Au+Ft+ PHY
# (PR #18 Lucid WR, PR #19 4 KiB bursts). No FT601 nets on the canvas.
# No NeoRV32. SRAM only (do not --write-flash).
#
# From platforms/alchitry-au-v2:
#   vivado -mode batch -source tcl/pvla_bd_example.tcl
#
# Optional before sourcing:
#   set pvla_num_ch    8
#   set pvla_phy       0
#   set pvla_has_axi   0
#   set skip_wrapper   0

if {![info exists pvla_num_ch]}  { set pvla_num_ch  8 }
if {![info exists pvla_phy]}     { set pvla_phy     0 }
if {![info exists pvla_has_axi]} { set pvla_has_axi 0 }
set pvla_board 2

if {$pvla_num_ch < 1 || $pvla_num_ch > 8} {
  error "pvla_num_ch must be 1-8 (got $pvla_num_ch)"
}

set script_dir  [file dirname [file normalize [info script]]]
set plat_dir    [file dirname $script_dir]
set repo_root   [file dirname [file dirname $plat_dir]]
set ip_repo     [file join $repo_root ip]
set project_dir [file join $plat_dir vivado_project_pvla_bd]
set part        xc7a35tftg256-1

puts "PVLA example BD (Au V2)"
puts "  channels : $pvla_num_ch"
puts "  PHY      : $pvla_phy   (0=FT601 Lucid WR / 4 KiB  1=STREAM)"
puts "  board    : AU_V2"
puts "  AXI-lite : $pvla_has_axi"
puts "  ip repo  : $ip_repo"

create_project -force pvla_bd $project_dir -part $part
set_property ip_repo_paths $ip_repo [current_project]
update_ip_catalog -rebuild

create_bd_design pvla_bd

create_bd_cell -type ip -vlnv greg676:user:pvla:1.0 pvla_0
set_property -dict [list \
  CONFIG.C_NUM_CH          $pvla_num_ch \
  CONFIG.C_SAMPLE_MHZ      {100} \
  CONFIG.C_PRETRIG_SAMPLES {4096} \
  CONFIG.C_PHY             $pvla_phy \
  CONFIG.C_BOARD           $pvla_board \
  CONFIG.C_HAS_AXI         $pvla_has_axi \
  CONFIG.C_INCLUDE_BR_XDC  {0} \
  CONFIG.C_DEFAULT_SOURCE  {0} \
] [get_bd_cells pvla_0]

make_bd_pins_external -name probe_i [get_bd_pins pvla_0/probe_i]
make_bd_pins_external -name status_o [get_bd_pins pvla_0/status_o]

if {$pvla_phy == 0} {
  make_bd_pins_external -name clk   [get_bd_pins pvla_0/clk]
  make_bd_pins_external -name rst_n [get_bd_pins pvla_0/rst_n]
  foreach p {ft_clk ft_wakeup ft_reset ft_rxf ft_txe ft_oe ft_rd ft_wr ft_be ft_data} {
    set pin [get_bd_pins -quiet pvla_0/$p]
    if {$pin eq ""} { continue }
    if {[get_bd_nets -quiet -of_objects $pin] ne ""} { continue }
    make_bd_pins_external -name $p $pin
  }
  puts "FT601 pads are wrapper ports (ft_*), not BD cell-to-cell nets."
} else {
  make_bd_pins_external -name sample_clk   [get_bd_pins pvla_0/sample_clk]
  make_bd_pins_external -name sample_rst_n [get_bd_pins pvla_0/sample_rst_n]
  make_bd_intf_pins_external -name m_axis [get_bd_intf_pins pvla_0/m_axis]
}

if {$pvla_has_axi} {
  make_bd_intf_pins_external -name s_axi [get_bd_intf_pins pvla_0/s_axi]
  make_bd_pins_external -name s_axi_aclk    [get_bd_pins pvla_0/s_axi_aclk]
  make_bd_pins_external -name s_axi_aresetn [get_bd_pins pvla_0/s_axi_aresetn]
}

regenerate_bd_layout
validate_bd_design -force
save_bd_design

if {![info exists skip_wrapper] || !$skip_wrapper} {
  make_wrapper -files [get_files pvla_bd.bd] -top
  set wrap [get_files -quiet *pvla_bd_wrapper.v]
  if {$wrap eq ""} {
    set wrap [get_files -quiet *pvla_bd_wrapper.vhd]
  }
  if {$wrap ne ""} {
    set_property top [file rootname [file tail $wrap]] [current_fileset]
  }
}

puts "Project: $project_dir/pvla_bd.xpr"
puts "RAM only: openFPGALoader --fpga-part xc7a35tftg256 --write-sram <bit>"
puts "Wrapper target: pvla_bd_wrapper"
