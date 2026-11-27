# Run synth+impl through write_bitstream on the current project.
# Callers set: project_dir, ft601_pinout (optional), impl_jobs (optional).
#
# From platforms/alchitry-platinum-v2, after create_project:
#   source [file join [file dirname [info script]] run_impl.tcl]

if {![info exists impl_jobs]} {
    set impl_jobs 8
}
if {![info exists ft601_pinout]} {
    set ft601_pinout "v2"
}
if {![info exists project_dir]} {
    set project_dir [get_property DIRECTORY [current_project]]
}

puts "Running impl (jobs=$impl_jobs, pinout=$ft601_pinout)"
launch_runs impl_1 -to_step write_bitstream -jobs $impl_jobs
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
puts "impl STATUS : $impl_status"
puts "impl WNS    : $wns ns"
puts "impl WHS    : $whs ns"
puts "impl TNS    : $tns ns"

set top [get_property top [current_fileset]]
if {![info exists project_name]} {
    set project_name [get_property NAME [current_project]]
}
set bit_src [file join $project_dir ${project_name}.runs impl_1 ${top}.bit]
if {![file exists $bit_src]} {
    set candidates [glob -nocomplain \
        [file join $project_dir *.runs impl_1 ${top}.bit] \
        [file join $project_dir * impl_1 ${top}.bit]]
    if {[llength $candidates]} {
        set bit_src [lindex $candidates 0]
    }
}

file mkdir ./bitstreams
if {![info exists ft601_mode]} {
    set ft601_mode "LOOPBACK"
}
if {$ft601_mode eq "TX_ONLY"} {
    set bit_name "ft601_tx_only_top_${ft601_pinout}.bit"
} elseif {$ft601_mode eq "RX_ONLY"} {
    set bit_name "ft601_rx_only_top_${ft601_pinout}.bit"
} else {
    set bit_name "${top}_${ft601_pinout}.bit"
}
set bit_dst [file normalize [file join ./bitstreams $bit_name]]
if {[file exists $bit_src]} {
    file copy -force $bit_src $bit_dst
    puts "bitstream   : $bit_src"
    puts "copy        : $bit_dst"
} else {
    puts "WARNING: bitstream not found for $top"
}

if {$wns eq "" || [catch {expr {$wns < 0.0}} wns_fail] || $wns_fail} {
    puts "TIMING NOT MET (WNS=$wns). Inspect the routed timing summary."
} else {
    puts "TIMING MET (WNS=$wns)."
}
