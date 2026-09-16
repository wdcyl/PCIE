set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ../..]]
set xpr [file join $project_root build vivado ax7103_an9238_pcie.xpr]
if {![file exists $xpr]} { source [file join $script_dir create_project.tcl] } else { open_project $xpr }
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }
open_run impl_1
report_timing_summary -file [file join $project_root build timing_summary.rpt]
report_drc -file [file join $project_root build drc.rpt]
puts "Bitstream and reports are under [file join $project_root build]"
