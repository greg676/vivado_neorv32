# ── rebuild_neorv_basic.tcl ─────────────────────────────────────
# Recreates the neorv_basic Vivado project from source files.
# Usage: vivado -mode batch -source tcl/rebuild_neorv_basic.tcl

set project_name "neorv_basic"
set project_dir  "./vivado_project"

# ── Create project ───────────────────────────────────────────
create_project -force $project_name $project_dir \
  -part xc7a100tfgg484-2

# ── Add constraints ──────────────────────────────────────────
add_files -fileset constrs_1 ./constraints/ptv2_basic.xdc

# ── Add RTL sources ──────────────────────────────────────────
add_files -fileset sources_1 ./rtl/neorv_basic_top.v

# ── Import block design ──────────────────────────────────────
# Block design must be re-created in Vivado GUI or imported:
# source ./bd/neorv_basic/neorv_basic.bd
# Note: .bd files reference IP paths that must exist.
# For full automation, use write_bd_tcl in Vivado to generate
# a TCL script, then source that instead.

puts "Project created. Open in Vivado GUI to import block design."
puts "  File → Open Block Design → bd/neorv_basic.bd"
puts "  Then: Generate Bitstream"
