# Recreate, synthesize, implement and generate a KC705 bitstream.
# Usage: vivado -mode batch -source fpga/kc705/tcl/build_bitstream.tcl
# Optional: -tclargs <project-directory> <parallel-jobs>

set script_dir  [file normalize [file dirname [info script]]]
set repo_root   [file normalize [file join $script_dir .. .. ..]]
set default_dir [file join $repo_root build vivado kc705]
set project_dir [expr {[llength $argv] >= 1 ? [file normalize [lindex $argv 0]] : $default_dir}]
set jobs        [expr {[llength $argv] >= 2 ? [lindex $argv 1] : 4}]

if {![string is integer -strict $jobs] || $jobs < 1} {
    error "parallel-jobs must be a positive integer"
}

set saved_argv $argv
set argv [list $project_dir]
source [file join $script_dir create_project.tcl]
set argv $saved_argv

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis did not complete successfully: $synth_status"
}

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "Implementation/bitstream generation failed: $impl_status"
}

set generated_bit [file join $project_dir pcie_kc705.runs impl_1 kc705_pcie_top.bit]
if {![file exists $generated_bit]} {
    error "Vivado reported completion but bitstream was not found: $generated_bit"
}

set artifact_dir [file join $repo_root build artifacts kc705]
file mkdir $artifact_dir
open_run impl_1
report_timing_summary -delay_type max -report_unconstrained \
    -file [file join $artifact_dir timing_summary.rpt]
report_drc -file [file join $artifact_dir drc.rpt]
report_utilization -file [file join $artifact_dir utilization.rpt]

set failing_paths [get_timing_paths -quiet -delay_type max \
    -slack_lesser_than 0.0 -max_paths 1]
if {[llength $failing_paths] != 0} {
    set worst_slack [get_property SLACK [lindex $failing_paths 0]]
    error "Bitstream exists, but implemented timing failed (WNS=$worst_slack ns)"
}

set artifact_bit [file join $artifact_dir kc705_pcie_top.bit]
file copy -force $generated_bit $artifact_bit
puts "Bitstream generated: $artifact_bit"
puts "Reports generated under: $artifact_dir"
