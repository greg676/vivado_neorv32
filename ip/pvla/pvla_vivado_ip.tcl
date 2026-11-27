# -- ================================================================================ --
# -- PVLA - Vivado IP Packaging & Customization GUI Setup                             --
# -- -------------------------------------------------------------------------------- --
# -- Mirrors rtl/system_integration/neorv32_vivado_ip.tcl from stnolting/neorv32     --
# -- (the catalog IP already used in this repo's Block Designs).                      --
# --                                                                                  --
# -- PHY RTL is the PR #18/#19 Lucid WR / 4 KiB burst core under                      --
# -- platforms/alchitry-au-v2/rtl/ft601/. NeoRV32 is not rewritten.                   --
# --                                                                                  --
# -- In Vivado TCL console, from the repo root or this file's directory:              --
# --   source ip/pvla/pvla_vivado_ip.tcl                                              --
# -- Then: Settings → IP → Repository → <repo>/ip                                     --
# -- -- ================================================================================ --

set script_path [file normalize [info script]]
set ip_dir      [file dirname $script_path]
set repo_root   [file normalize [file join $ip_dir ../..]]
set au          [file join $repo_root platforms/alchitry-au-v2]
set outputdir   [file join $ip_dir work]
set ip_top      pvla

file mkdir $outputdir
set files [glob -nocomplain "$outputdir/*"]
if {[llength $files] != 0} {
  file delete -force {*}[glob -directory $outputdir *]
}

create_project "pvla-ip" $outputdir -part xc7a100tfgg484-2 -force
set_property INCREMENTAL false [get_filesets sim_1]

set file_list [list \
  [file join $au rtl/ft601/ft601_sync_fifo.v] \
  [file join $au rtl/ft601/ft601_reset.v] \
  [file join $ip_dir hdl/pvla_axi_lite.v] \
  [file join $ip_dir hdl/pvla_capture.v] \
  [file join $ip_dir hdl/pvla.v] \
]

set xdc_list [list \
  [file join $ip_dir xdc/ftplus_ft601_pt_alpha.xdc] \
  [file join $ip_dir xdc/ftplus_ft601_pt_v2.xdc] \
  [file join $ip_dir xdc/ftplus_ft601_au_v2.xdc] \
  [file join $ip_dir xdc/ftplus_ft601_timing.xdc] \
  [file join $ip_dir xdc/ftplus_ft601_impl.xdc] \
  [file join $ip_dir xdc/br_bank_a_8ch.xdc] \
]

add_files $file_list
add_files -fileset constrs_1 $xdc_list
set_property used_in_synthesis false [get_files -quiet *ftplus_ft601_impl.xdc]
set_property top $ip_top [current_fileset]
update_compile_order -fileset sources_1

# Package in-place so <repo>/ip is a valid catalog path (like adding the
# NEORV32 packaged_ip folder).
ipx::package_project -root_dir $ip_dir -vendor greg676 -library user \
  -taxonomy /UserIP -import_files false -set_current true -force

set_property vendor greg676 [ipx::current_core]
set_property library user [ipx::current_core]
set_property name pvla [ipx::current_core]
set_property version 1.0 [ipx::current_core]
set_property display_name "PVLA" [ipx::current_core]
set_property vendor_display_name "greg676" [ipx::current_core]
set_property company_url https://github.com/greg676/vivado_neorv32 [ipx::current_core]
set_property description "PulseView logic analyzer (1-8 ch). FT601 Lucid WR / 4 KiB bursts; pins in an IP-scoped Ft+ XDC, not BD nets. No DDR3." [ipx::current_core]
set_property supported_families {artix7 Production artix7 Production} [ipx::current_core]

# ── Infer AXI / AXIS / clocks ───────────────────────────────────
ipx::infer_bus_interface s_axi_aclk xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interface clk xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interface sample_clk xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interface ft_clk xilinx.com:signal:clock_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interface s_axi_aresetn xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interface rst_n xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interface sample_rst_n xilinx.com:signal:reset_rtl:1.0 [ipx::current_core]
ipx::infer_bus_interfaces [ipx::current_core]

ipx::associate_bus_interfaces -busif s_axi -clock s_axi_aclk [ipx::current_core]
ipx::associate_bus_interfaces -clock s_axi_aclk -reset s_axi_aresetn [ipx::current_core]
catch { ipx::associate_bus_interfaces -busif m_axis -clock sample_clk [ipx::current_core] }

# ── User parameters ─────────────────────────────────────────────
proc pvla_user_param { name default fmt {min ""} {max ""} } {
  ipx::add_user_parameter $name [ipx::current_core]
  set p [ipx::get_user_parameters $name -of_objects [ipx::current_core]]
  set_property value_resolve_type user $p
  set_property value $default $p
  set_property value_format $fmt $p
  if {$min ne ""} {
    set_property value_validation_type range_long $p
    set_property value_validation_range_minimum $min $p
    set_property value_validation_range_maximum $max $p
  }
  # HDL generic of the same name
  set m [ipx::get_hdl_parameters $name -of_objects [ipx::current_core]]
  if {$m ne ""} {
    set_property value $default $m
    set_property value_format $fmt $m
    set_property value_resolve_type generated $m
  }
}

pvla_user_param C_NUM_CH          8    long 1 8
pvla_user_param C_SAMPLE_MHZ      200  long
pvla_user_param C_PRETRIG_SAMPLES 4096 long
pvla_user_param C_DEFAULT_POST    2048 long
pvla_user_param C_PHY             0    long
pvla_user_param C_BOARD           0    long
pvla_user_param C_HAS_AXI         1    long
pvla_user_param C_INCLUDE_BR_XDC  0    long
pvla_user_param C_DEFAULT_SOURCE  2    long

set_property value_validation_type pairs [ipx::get_user_parameters C_PHY -of_objects [ipx::current_core]]
set_property value_validation_pairs {{FT601} 0 {STREAM} 1} [ipx::get_user_parameters C_PHY -of_objects [ipx::current_core]]

set_property value_validation_type pairs [ipx::get_user_parameters C_BOARD -of_objects [ipx::current_core]]
set_property value_validation_pairs {{PT_ALPHA} 0 {PT_V2} 1 {AU_V2} 2} [ipx::get_user_parameters C_BOARD -of_objects [ipx::current_core]]

set_property value_validation_type pairs [ipx::get_user_parameters C_HAS_AXI -of_objects [ipx::current_core]]
set_property value_validation_pairs {{Disabled} 0 {Enabled} 1} [ipx::get_user_parameters C_HAS_AXI -of_objects [ipx::current_core]]

set_property value_validation_type pairs [ipx::get_user_parameters C_INCLUDE_BR_XDC -of_objects [ipx::current_core]]
set_property value_validation_pairs {{No (user-wired)} 0 {Yes (Br Bank A)} 1} [ipx::get_user_parameters C_INCLUDE_BR_XDC -of_objects [ipx::current_core]]

set_property value_validation_type pairs [ipx::get_user_parameters C_SAMPLE_MHZ -of_objects [ipx::current_core]]
set_property value_validation_pairs {{100 MS/s SDR} 100 {200 MS/s DDR} 200} [ipx::get_user_parameters C_SAMPLE_MHZ -of_objects [ipx::current_core]]

set_property value_validation_type pairs [ipx::get_user_parameters C_DEFAULT_SOURCE -of_objects [ipx::current_core]]
set_property value_validation_pairs {{Counter} 0 {Walking-one} 1 {Live probes} 2} [ipx::get_user_parameters C_DEFAULT_SOURCE -of_objects [ipx::current_core]]

# ── Port enablement (hide FT601 from STREAM; hide AXIS from FT601) ─
set_property enablement_dependency {$C_PHY == 0} [ipx::get_ports ft_* -of_objects [ipx::current_core]]
set_property enablement_dependency {$C_PHY == 1} [ipx::get_ports m_axis_* -of_objects [ipx::current_core]]
set_property enablement_dependency {$C_PHY == 1} [ipx::get_ports sample_clk -of_objects [ipx::current_core]]
set_property enablement_dependency {$C_PHY == 1} [ipx::get_ports sample_rst_n -of_objects [ipx::current_core]]
set_property enablement_dependency {$C_PHY == 0} [ipx::get_ports clk -of_objects [ipx::current_core]]
set_property enablement_dependency {$C_PHY == 0} [ipx::get_ports rst_n -of_objects [ipx::current_core]]
set_property enablement_dependency {$C_HAS_AXI != 0} [ipx::get_ports s_axi_* -of_objects [ipx::current_core]]
catch { set_property enablement_dependency {$C_PHY == 1} [ipx::get_bus_interfaces m_axis -of_objects [ipx::current_core]] }
catch { set_property enablement_dependency {$C_HAS_AXI != 0} [ipx::get_bus_interfaces s_axi -of_objects [ipx::current_core]] }

# probe_i width follows C_NUM_CH (HDL parameter already drives the port)

# ── Scoped XDCs (MIG-style pin files, attached to this instance) ─
proc pvla_add_xdc { relpath {synth 1} } {
  set core [ipx::current_core]
  set fg [ipx::get_file_groups xilinx_implementation -of_objects $core]
  if {$fg eq ""} {
    ipx::add_file_group -type implementation xilinx_implementation $core
    set fg [ipx::get_file_groups xilinx_implementation -of_objects $core]
  }
  ipx::add_file $relpath $fg
  set f [ipx::get_files $relpath -of_objects $fg]
  set_property type xdc $f
  if {$synth} {
    set_property used_in {synthesis implementation} $f
  } else {
    set_property used_in {implementation} $f
  }
  catch { set_property scoped_to_ref pvla $f }
  return $f
}

set f_alpha [pvla_add_xdc xdc/ftplus_ft601_pt_alpha.xdc 1]
set f_v2    [pvla_add_xdc xdc/ftplus_ft601_pt_v2.xdc 1]
set f_au    [pvla_add_xdc xdc/ftplus_ft601_au_v2.xdc 1]
set f_time  [pvla_add_xdc xdc/ftplus_ft601_timing.xdc 1]
set f_impl  [pvla_add_xdc xdc/ftplus_ft601_impl.xdc 0]
set f_br    [pvla_add_xdc xdc/br_bank_a_8ch.xdc 1]

set_property enablement_tcl_expr {$C_PHY == 0 && $C_BOARD == 0} $f_alpha
set_property enablement_tcl_expr {$C_PHY == 0 && $C_BOARD == 1} $f_v2
set_property enablement_tcl_expr {$C_PHY == 0 && $C_BOARD == 2} $f_au
set_property enablement_tcl_expr {$C_PHY == 0} $f_time
set_property enablement_tcl_expr {$C_PHY == 0} $f_impl
set_property enablement_tcl_expr {$C_INCLUDE_BR_XDC != 0} $f_br

# ── GUI (same helpers as NEORV32) ───────────────────────────────
proc setup_ip_gui {} {
  proc set_param_properties {name {display_name ""} {tooltip ""} {enablement_expr ""} {value_expr ""}} {
    set param_spec [ipgui::get_guiparamspec -name $name -component [ipx::current_core]]
    set user_param [ipx::get_user_parameters $name -of_objects [ipx::current_core]]
    if {$display_name ne ""} {
      set_property display_name $display_name $param_spec
    }
    if {$tooltip ne ""} {
      set_property tooltip $tooltip $param_spec
    }
    if {$enablement_expr ne ""} {
      set_property enablement_tcl_expr $enablement_expr $user_param
    }
    if {$value_expr ne ""} {
      set_property value_tcl_expr $value_expr $user_param
    }
  }

  set page [ipgui::get_pagespec -name "Page 0" -component [ipx::current_core]]
  if {$page ne ""} {
    ipgui::remove_page -component [ipx::current_core] $page
  }

  set page [ipgui::add_page -name {General} -component [ipx::current_core] -display_name {General}]
  ipgui::add_static_text -name {About} -component [ipx::current_core] -parent $page \
    -text {PVLA is a fabric logic analyzer that streams to PulseView. User designs keep MIG7/DDR. FT601 pins live in an Ft+ board XDC (SCOPED_TO_REF), not wires on the BD. PHY is Lucid DATA-before-WR with 4 KiB bursts (PR #18/#19).}

  set g [ipgui::add_group -name {Capture} -component [ipx::current_core] -parent $page -display_name {Capture}]
  foreach n {C_NUM_CH C_SAMPLE_MHZ C_PRETRIG_SAMPLES C_DEFAULT_POST C_DEFAULT_SOURCE} {
    ipgui::add_param -name $n -component [ipx::current_core] -parent $g
  }
  set_param_properties C_NUM_CH {Channels (1-8)} {Resizes probe_i. Unused channels pad to 0.}
  set_param_properties C_SAMPLE_MHZ {Sample rate} {200 MS/s first cut (DDR @ 100 MHz). 100 = SDR. 400 later.}
  set_param_properties C_PRETRIG_SAMPLES {Pre-trigger BRAM depth} {Power of two. Not DDR3. Live dumps in 4 KiB PHY bursts.}
  set_param_properties C_DEFAULT_POST {Default post-trigger samples} {}
  set_param_properties C_DEFAULT_SOURCE {Default source} {Counter / walking-one / live probes}

  set g [ipgui::add_group -name {PHY} -component [ipx::current_core] -parent $page -display_name {PHY and board}]
  foreach n {C_PHY C_BOARD C_INCLUDE_BR_XDC} {
    ipgui::add_param -name $n -component [ipx::current_core] -parent $g
  }
  set_param_properties C_PHY {PHY} {FT601 pads are auto-pinned. STREAM exposes m_axis_* .}
  set_param_properties C_BOARD {Ft+ board pinout} {PT_ALPHA first-batch DATA[0:13]; PT_V2 production Pt; AU_V2 Au.} {$C_PHY == 0}
  set_param_properties C_INCLUDE_BR_XDC {Include Br Bank A probe XDC} {Optional. Probe ports stay user-wired unless enabled. Pt only.}

  set g [ipgui::add_group -name {AXI} -component [ipx::current_core] -parent $page -display_name {AXI4-Lite}]
  ipgui::add_param -name C_HAS_AXI -component [ipx::current_core] -parent $g
  set_param_properties C_HAS_AXI {AXI4-Lite slave} {Arm / trigger / status. Same command word as the FT601 host path.}
}

setup_ip_gui

# ── BD Tcl + GUI + upgrade ──────────────────────────────────────
set bd_grp [ipx::add_file_group -type {block_diagram_automation} {} [ipx::current_core]]
ipx::add_file bd/bd.tcl [ipx::get_file_groups xilinx_blockdiagramautomation -of_objects [ipx::current_core]]

set_property previous_version_for_upgrade greg676:user:pvla:1.0 [ipx::current_core]
set_property core_revision 2 [ipx::current_core]

ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]

set_property ip_repo_paths $ip_dir [current_project]
update_ip_catalog

puts "PVLA packaged at $ip_dir"
puts "Add IP repository: $repo_root/ip"
puts "VLNV: greg676:user:pvla:1.0"
puts "PHY: platforms/alchitry-au-v2/rtl/ft601 (Lucid WR, 4 KiB, ALWAYS_DRIVE)"

close_project
