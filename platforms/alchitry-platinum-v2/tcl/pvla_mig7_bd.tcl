# ── pvla_mig7_bd.tcl ────────────────────────────────────────────
# Pt-only BD: clk_wiz + MIG7 256 MB + SmartConnect. No NeoRV32.
# Fabric AXI4 master (pvla_mig7_capture_core) is S00_AXI on the wrapper.
# FT601 PHY stays in Verilog (4 KiB Lucid WR). Do not program QSPI.
#
# From platforms/alchitry-platinum-v2:
#   vivado -mode batch -source tcl/pvla_mig7_bd.tcl
#
# Optional:
#   set skip_wrapper 1
#   set mig_prj [file join $plat_dir mig mig_pt_v2.prj]
#
# Clocking matches neorv_basic_plus_vivado.bd:
#   clk 100 MHz -> clk_out1 100 MHz sys_clk_i
#                 clk_out2 200 MHz clk_ref_i
# MIG window 256 MB @ 0x20000000. DDR pins stay in the MIG IP.

if {![info exists skip_wrapper]} { set skip_wrapper 0 }

set script_dir  [file dirname [file normalize [info script]]]
set plat_dir    [file dirname $script_dir]
set project_dir [file join $plat_dir vivado_project_pvla_mig7]
set part        xc7a100tfgg484-2
set mig_prj ""
foreach cand {mig_b.prj mig_pt_v2.prj} {
  set p [file join $plat_dir mig $cand]
  if {[file exists $p]} {
    set mig_prj $p
    break
  }
}
if {$mig_prj eq ""} {
  set mig_prj [file join $plat_dir mig mig_b.prj]
}

puts "PVLA MIG7 BD (Pt V2, no CPU)"
puts "  part    : $part"
puts "  mig prj : $mig_prj"
puts "  DDR     : 256 MB @ 0x20000000 (neorv_basic_plus pinout)"
puts "  CPU     : none (fabric AXI master)"

create_project -force pvla_mig7 $project_dir -part $part
create_bd_design pvla_mig7_bd

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {100.000} \
  CONFIG.CLKOUT1_USED {true} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
  CONFIG.CLKOUT2_USED {true} \
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {200.000} \
  CONFIG.NUM_OUT_CLKS {2} \
  CONFIG.RESET_TYPE {ACTIVE_LOW} \
  CONFIG.RESET_PORT {resetn} \
] [get_bd_cells clk_wiz_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:4.2 mig_7series_0
set_property CONFIG.BOARD_MIG_PARAM {Custom} [get_bd_cells mig_7series_0]
if {[file exists $mig_prj]} {
  set_property CONFIG.XML_INPUT_FILE $mig_prj [get_bd_cells mig_7series_0]
  puts "Applied $mig_prj"
} else {
  puts "WARNING: $mig_prj missing."
  puts "Copy mig_b.prj from the proven neorv_basic_plus MIG (see mig/README.md)."
}

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0
set_property CONFIG.NUM_SI {1} [get_bd_cells smartconnect_0]

make_bd_pins_external        -name clk    [get_bd_pins clk_wiz_0/clk_in1]
make_bd_pins_external        -name resetn [get_bd_pins clk_wiz_0/resetn]
make_bd_intf_pins_external   -name DDR3_0 [get_bd_intf_pins mig_7series_0/DDR3]
make_bd_intf_pins_external   -name S00_AXI [get_bd_intf_pins smartconnect_0/S00_AXI]
set_property CONFIG.DATA_WIDTH {128} [get_bd_intf_ports S00_AXI]
set_property CONFIG.ID_WIDTH   {0}   [get_bd_intf_ports S00_AXI]
set_property CONFIG.PROTOCOL   {AXI4} [get_bd_intf_ports S00_AXI]

connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins mig_7series_0/sys_clk_i]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins mig_7series_0/clk_ref_i]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins mig_7series_0/S_AXI]
connect_bd_net [get_bd_pins mig_7series_0/ui_clk] [get_bd_pins smartconnect_0/aclk]

# sys_rst active-high: invert board resetn (locked also ANDed in wrapper if needed)
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 inv_rst
set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {not}] [get_bd_cells inv_rst]
connect_bd_net [get_bd_pins clk_wiz_0/resetn] [get_bd_pins inv_rst/Op1]
connect_bd_net [get_bd_pins inv_rst/Res]      [get_bd_pins mig_7series_0/sys_rst]

create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 inv_ui_rst
set_property -dict [list CONFIG.C_SIZE {1} CONFIG.C_OPERATION {not}] [get_bd_cells inv_ui_rst]
connect_bd_net [get_bd_pins mig_7series_0/ui_clk_sync_rst] [get_bd_pins inv_ui_rst/Op1]
connect_bd_net [get_bd_pins inv_ui_rst/Res] [get_bd_pins smartconnect_0/aresetn]
connect_bd_net [get_bd_pins inv_ui_rst/Res] [get_bd_pins mig_7series_0/aresetn]

make_bd_pins_external -name ui_clk              [get_bd_pins mig_7series_0/ui_clk]
make_bd_pins_external -name ui_clk_sync_rst     [get_bd_pins mig_7series_0/ui_clk_sync_rst]
make_bd_pins_external -name init_calib_complete [get_bd_pins mig_7series_0/init_calib_complete]

assign_bd_address -offset 0x20000000 -range 256M \
  [get_bd_addr_segs mig_7series_0/memmap/memaddr]

regenerate_bd_layout
if {[catch {validate_bd_design -force} err]} {
  puts "validate_bd_design: $err"
}
save_bd_design

if {!$skip_wrapper} {
  make_wrapper -files [get_files pvla_mig7_bd.bd] -top
}

puts "Project: $project_dir/pvla_mig7.xpr"
puts "No NeoRV32. No QSPI. RAM program later."
