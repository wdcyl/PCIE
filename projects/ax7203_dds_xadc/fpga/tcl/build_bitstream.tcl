set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ../..]]
set project_file [file join $project_root build vivado ax7203_xadc_xdma.xpr]
if {![file exists $project_file]} {
    source [file join $script_dir create_project.tcl]
} else {
    open_project $project_file
}
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed" }
puts "Bitstream: [file join $project_root build vivado ax7203_xadc_xdma.runs impl_1 ax7203_xdma_top.bit]"
