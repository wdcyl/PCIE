# Recreate the KC705 Vivado project and its single 7-Series PCIe IP instance.
# Usage: vivado -mode batch -source fpga/kc705/tcl/create_project.tcl
# Optional: -tclargs <project-directory>

set script_dir  [file normalize [file dirname [info script]]]
set repo_root   [file normalize [file join $script_dir .. .. ..]]
set default_dir [file join $repo_root build vivado kc705]
set project_dir [expr {[llength $argv] >= 1 ? [file normalize [lindex $argv 0]] : $default_dir}]
set project_name pcie_kc705
set top_name     kc705_pcie_top
set part_name    xc7k325tffg900-2

file mkdir $project_dir
create_project -force $project_name $project_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

set rtl_dir [file join $repo_root rtl]
set rtl_files [list \
    [file join $rtl_dir async_fifo.sv] \
    [file join $rtl_dir adc_pattern_source.sv] \
    [file join $rtl_dir acquisition_controller.sv] \
    [file join $rtl_dir bar_registers.sv] \
    [file join $rtl_dir c2h_dma_engine.sv] \
    [file join $rtl_dir pcie_tlp_endpoint.sv] \
    [file join $rtl_dir tlp_tx_arbiter.sv] \
    [file join $rtl_dir pcie_acq_top.sv] \
    [file join $rtl_dir xilinx_7x_axis_bridge_64.sv] \
    [file join $rtl_dir xilinx_7x_msi_controller.sv] \
    [file join $repo_root fpga kc705 rtl kc705_pcie_top.sv] \
]
foreach source_file $rtl_files {
    if {![file exists $source_file]} {
        error "Required RTL source does not exist: $source_file"
    }
}
add_files -norecurse $rtl_files
set_property include_dirs [list $rtl_dir] [get_filesets sources_1]

set xdc_file [file join $repo_root fpga kc705 constraints kc705_pcie.xdc]
if {![file exists $xdc_file]} {
    error "Required constraints file does not exist: $xdc_file"
}
add_files -fileset constrs_1 -norecurse $xdc_file

# Pin the IP version so the user interface cannot silently change.
set pcie_vlnv xilinx.com:ip:pcie_7x:3.3
if {[llength [get_ipdefs -all $pcie_vlnv]] == 0} {
    error "Vivado installation does not provide required IP $pcie_vlnv"
}

# Exactly one pcie_7x instance is generated here and instantiated once by
# kc705_pcie_top. The IP owns config space, LTSSM, DLL, PHY and MSI messages.
create_ip -vlnv $pcie_vlnv -module_name pcie_7x_0 -dir [file join $project_dir ip]
set pcie_ip [get_ips pcie_7x_0]
set_property -dict [list \
    CONFIG.mode_selection {Advanced} \
    CONFIG.Device_Port_Type {PCI_Express_Endpoint_device} \
    CONFIG.Maximum_Link_Width {X4} \
    CONFIG.Link_Speed {5.0_GT/s} \
    CONFIG.Interface_Width {64_bit} \
    CONFIG.User_Clk_Freq {250} \
    CONFIG.Ref_Clk_Freq {100_MHz} \
    CONFIG.Bar0_Enabled {true} \
    CONFIG.Bar0_Type {Memory} \
    CONFIG.Bar0_64bit {false} \
    CONFIG.Bar0_Prefetchable {false} \
    CONFIG.Bar0_Scale {Kilobytes} \
    CONFIG.Bar0_Size {4} \
    CONFIG.Bar1_Enabled {false} \
    CONFIG.Bar2_Enabled {false} \
    CONFIG.Bar3_Enabled {false} \
    CONFIG.Bar4_Enabled {false} \
    CONFIG.Bar5_Enabled {false} \
    CONFIG.Expansion_Rom_Enabled {false} \
    CONFIG.MSI_Enabled {true} \
    CONFIG.MSI_64b {true} \
    CONFIG.Multiple_Message_Capable {1_vector} \
    CONFIG.MSIx_Enabled {false} \
    CONFIG.IntX_Generation {false} \
    CONFIG.AER_Enabled {false} \
    CONFIG.rcv_msg_if {false} \
    CONFIG.cfg_fc_if {false} \
    CONFIG.err_reporting_if {false} \
    CONFIG.en_ext_clk {false} \
    CONFIG.shared_logic_in_core {false} \
    CONFIG.en_ext_gt_common {false} \
    CONFIG.en_ext_ch_gt_drp {false} \
    CONFIG.en_transceiver_status_ports {false} \
    CONFIG.en_ext_pipe_interface {false} \
    CONFIG.PCIe_Debug_Ports {true} \
    CONFIG.Receive_NP_Request {true} \
    CONFIG.pl_interface {true} \
    CONFIG.cfg_mgmt_if {true} \
    CONFIG.cfg_ctl_if {true} \
    CONFIG.cfg_status_if {true} \
    CONFIG.Xlnx_Ref_Board {KC705} \
    CONFIG.PCIe_Blk_Locn {X0Y0} \
] $pcie_ip

# Fail early if Vivado normalized or rejected a setting in a way that would
# change the RTL boundary or the negotiated capabilities expected by this top.
set required_config [list \
    Maximum_Link_Width X4 \
    Link_Speed 5.0_GT/s \
    Interface_Width 64_bit \
    User_Clk_Freq 250 \
    Bar0_Size 4 \
    MSI_Enabled true \
    Multiple_Message_Capable 1_vector \
    err_reporting_if false \
    cfg_fc_if false \
    en_ext_clk false \
    en_ext_pipe_interface false \
    PCIe_Debug_Ports true \
]
foreach {property_name expected_value} $required_config {
    set actual_value [get_property CONFIG.$property_name $pcie_ip]
    if {$actual_value ne $expected_value} {
        error "PCIe IP setting CONFIG.$property_name is '$actual_value', expected '$expected_value'"
    }
}

generate_target all $pcie_ip
set_property top $top_name [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "KC705 project created: [file join $project_dir ${project_name}.xpr]"
puts "Target: $part_name; PCIe: Gen2 x4, 64-bit AXI4-Stream at 250 MHz"
puts "BAR0: 4 KiB memory; interrupt: one-vector, 64-bit-capable MSI"
