# Recreate the AX7203 XDMA/XADC project. Run in Vivado Tcl mode.
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ../..]]
set project_dir [file join $project_root build vivado]

create_project -force ax7203_xadc_xdma $project_dir -part xc7a200tfbg484-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    [file join $project_root rtl async_fifo.sv] \
    [file join $project_root rtl xadc_acquisition_controller.sv] \
    [file join $project_root rtl xadc_axis_packer.sv] \
    [file join $project_root rtl axis_stress_source.sv] \
    [file join $project_root rtl axil_control_regs.sv] \
    [file join $project_root rtl xadc_xdma_core.sv] \
    [file join $project_root rtl xadc_sampler.sv] \
    [file join $project_root rtl ad9833_controller.sv] \
    [file join $project_root fpga rtl xdma_subsystem.sv] \
    [file join $project_root fpga rtl ax7203_xdma_top.sv]]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $project_root fpga constraints ax7203.xdc]

create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
set ip [get_ips xdma_0]
proc require_ip_property {ip name value} {
    if {[lsearch -exact [list_property $ip] $name] < 0} {
        error "Required XDMA property $name is unavailable. See docs/HARDWARE_BRINGUP.md."
    }
    set_property $name $value $ip
}
require_ip_property $ip CONFIG.mode_selection Advanced
require_ip_property $ip CONFIG.functional_mode DMA
require_ip_property $ip CONFIG.device_port_type PCI_Express_Endpoint_device
require_ip_property $ip CONFIG.pl_link_cap_max_link_width X4
require_ip_property $ip CONFIG.pl_link_cap_max_link_speed 5.0_GT/s
require_ip_property $ip CONFIG.axi_data_width 128_bit
require_ip_property $ip CONFIG.axisten_freq 125
require_ip_property $ip CONFIG.xdma_axi_intf_mm AXI_Stream
require_ip_property $ip CONFIG.xdma_rnum_chnl 1
require_ip_property $ip CONFIG.xdma_wnum_chnl 1
require_ip_property $ip CONFIG.axilite_master_en true
require_ip_property $ip CONFIG.xdma_num_usr_irq 1
require_ip_property $ip CONFIG.pf0_msi_enabled true
require_ip_property $ip CONFIG.vendor_id 10EE
require_ip_property $ip CONFIG.pf0_device_id 7024
generate_target all $ip

set_property top ax7203_xdma_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Created project: $project_dir"
