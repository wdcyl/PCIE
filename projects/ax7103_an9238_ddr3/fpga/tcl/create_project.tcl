# Rebuild AX7103 + AN9238 + DDR3 + XDMA design in Vivado.
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir ../..]]
set build_dir [file join $project_root build vivado]
create_project -force ax7103_an9238_pcie $build_dir -part xc7a100tfgg484-2
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    [file join $project_root rtl ad9833_controller.sv] \
    [file join $project_root rtl async_fifo.sv] \
    [file join $project_root rtl an9238_capture.sv] \
    [file join $project_root rtl fifo_stream_adapter.sv] \
    [file join $project_root rtl axi_test_source.sv] \
    [file join $project_root rtl axi_burst_writer.sv] \
    [file join $project_root rtl axil_acquisition_regs.sv] \
    [file join $project_root rtl acquisition_ddr_core.sv] \
    [file join $project_root fpga rtl acquisition_ddr_bd_adapter.sv]]
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $project_root fpga constraints ax7103_an9238.xdc]
update_compile_order -fileset sources_1

proc set_required {cell property value} {
    if {[lsearch -exact [list_property $cell] $property] < 0} {
        error "Required IP property $property is unavailable on $cell"
    }
    set_property $property $value $cell
}

create_bd_design system

set xdma [create_bd_cell -type ip -vlnv xilinx.com:ip:xdma:* xdma_0]
set_required $xdma CONFIG.functional_mode DMA
set_required $xdma CONFIG.device_port_type PCI_Express_Endpoint_device
set_required $xdma CONFIG.pl_link_cap_max_link_width X4
set_required $xdma CONFIG.pl_link_cap_max_link_speed 5.0_GT/s
set_required $xdma CONFIG.axi_data_width 128_bit
set_required $xdma CONFIG.axisten_freq 125
set_required $xdma CONFIG.xdma_axi_intf_mm AXI_Memory_Mapped
set_required $xdma CONFIG.xdma_rnum_chnl 1
set_required $xdma CONFIG.xdma_wnum_chnl 1
set_required $xdma CONFIG.axilite_master_en true
set_required $xdma CONFIG.vendor_id 10EE
set_required $xdma CONFIG.pf0_device_id 7103
if {[lsearch -exact [list_property $xdma] CONFIG.pcie_blk_locn] >= 0} {
    set_property CONFIG.pcie_blk_locn X0Y0 $xdma
}

set mig [create_bd_cell -type ip -vlnv xilinx.com:ip:mig_7series:* mig_0]
set_required $mig CONFIG.XML_INPUT_FILE [file join $project_root fpga ip ax7103_mig.prj]

set pcie_buf [create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf:* pcie_refclk_buf]
set_property -dict [list CONFIG.C_BUF_TYPE {IBUFDSGTE}] $pcie_buf
set ddr_clk [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:* ddr_clk_wiz]
set_property -dict [list CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ {200.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {200.000} \
    CONFIG.RESET_TYPE {ACTIVE_LOW}] $ddr_clk
set adc_clk [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:* adc_clk_wiz]
set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer} CONFIG.PRIM_IN_FREQ {100.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {65.000} CONFIG.RESET_TYPE {ACTIVE_LOW}] $adc_clk

set mem_cdc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:* mem_cdc]
set ctrl_cdc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:* ctrl_cdc]
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.DATA_WIDTH {32} CONFIG.ADDR_WIDTH {32}] $ctrl_cdc
set axi_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* ddr_interconnect]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $axi_ic
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* mig_reset]
set acq [create_bd_cell -type module -reference acquisition_ddr_bd_adapter acq_0]

# External physical interfaces.
make_bd_intf_pins_external [get_bd_intf_pins $xdma/pcie_mgt]
set_property name pci_exp [get_bd_intf_ports pcie_mgt_0]
make_bd_intf_pins_external [get_bd_intf_pins $pcie_buf/CLK_IN_D]
set_property name pcie_refclk [get_bd_intf_ports CLK_IN_D_0]
make_bd_intf_pins_external [get_bd_intf_pins $ddr_clk/CLK_IN1_D]
set_property name ddr_refclk [get_bd_intf_ports CLK_IN1_D_0]
make_bd_intf_pins_external [get_bd_intf_pins $mig/DDR3]
set_property name ddr3 [get_bd_intf_ports DDR3_0]

set pcie_perst_n [create_bd_port -dir I -type rst pcie_perst_n]
set_property CONFIG.POLARITY ACTIVE_LOW $pcie_perst_n
set board_reset_n [create_bd_port -dir I -type rst board_reset_n]
set_property CONFIG.POLARITY ACTIVE_LOW $board_reset_n
set adc_ch0 [create_bd_port -dir I -from 11 -to 0 adc_ch0]
set adc_ch1 [create_bd_port -dir I -from 11 -to 0 adc_ch1]
set adc_clk_ch0 [create_bd_port -dir O -type clk adc_clk_ch0]
set adc_clk_ch1 [create_bd_port -dir O -type clk adc_clk_ch1]
set dds_sclk [create_bd_port -dir O dds_sclk]
set dds_fsync_n [create_bd_port -dir O dds_fsync_n]
set dds_sdata [create_bd_port -dir O dds_sdata]

# Clock and reset tree.
connect_bd_net [get_bd_pins $pcie_buf/IBUF_OUT] [get_bd_pins $xdma/sys_clk_gt]
connect_bd_net [get_bd_pins $pcie_buf/IBUF_DS_ODIV2] [get_bd_pins $xdma/sys_clk]
connect_bd_net $pcie_perst_n [get_bd_pins $xdma/sys_rst_n]
connect_bd_net $board_reset_n [get_bd_pins $ddr_clk/resetn] [get_bd_pins $mig/sys_rst]
connect_bd_net [get_bd_pins $ddr_clk/clk_out1] [get_bd_pins $mig/sys_clk_i]
connect_bd_net [get_bd_pins $mig/ui_clk] [get_bd_pins $rst/slowest_sync_clk] \
    [get_bd_pins $adc_clk/clk_in1] [get_bd_pins $axi_ic/ACLK] \
    [get_bd_pins $axi_ic/S00_ACLK] [get_bd_pins $axi_ic/S01_ACLK] [get_bd_pins $axi_ic/M00_ACLK] \
    [get_bd_pins $mem_cdc/m_axi_aclk] [get_bd_pins $ctrl_cdc/m_axi_aclk] [get_bd_pins $acq/ctrl_clk]
connect_bd_net [get_bd_pins $mig/ui_clk_sync_rst] [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $mig/init_calib_complete] [get_bd_pins $rst/dcm_locked] [get_bd_pins $acq/calib_done]
connect_bd_net [get_bd_pins $rst/peripheral_aresetn] [get_bd_pins $adc_clk/resetn] \
    [get_bd_pins $axi_ic/ARESETN] [get_bd_pins $axi_ic/S00_ARESETN] [get_bd_pins $axi_ic/S01_ARESETN] \
    [get_bd_pins $axi_ic/M00_ARESETN] [get_bd_pins $mig/aresetn] [get_bd_pins $mem_cdc/m_axi_aresetn] \
    [get_bd_pins $ctrl_cdc/m_axi_aresetn] [get_bd_pins $acq/ctrl_resetn]
connect_bd_net [get_bd_pins $xdma/axi_aclk] [get_bd_pins $mem_cdc/s_axi_aclk] [get_bd_pins $ctrl_cdc/s_axi_aclk]
connect_bd_net [get_bd_pins $xdma/axi_aresetn] [get_bd_pins $mem_cdc/s_axi_aresetn] [get_bd_pins $ctrl_cdc/s_axi_aresetn]
connect_bd_net [get_bd_pins $xdma/user_lnk_up] [get_bd_pins $acq/link_up]
connect_bd_net [get_bd_pins $adc_clk/clk_out1] [get_bd_pins $acq/adc_clk] $adc_clk_ch0 $adc_clk_ch1
connect_bd_net [get_bd_pins $rst/peripheral_aresetn] [get_bd_pins $acq/adc_resetn]
connect_bd_net $adc_ch0 [get_bd_pins $acq/adc_ch0]
connect_bd_net $adc_ch1 [get_bd_pins $acq/adc_ch1]
connect_bd_net $dds_sclk [get_bd_pins $acq/dds_sclk]
connect_bd_net $dds_fsync_n [get_bd_pins $acq/dds_fsync_n]
connect_bd_net $dds_sdata [get_bd_pins $acq/dds_sdata]

# PCIe DMA reads/writes the memory map; acquisition is a second AXI master.
connect_bd_intf_net [get_bd_intf_pins $xdma/M_AXI] [get_bd_intf_pins $mem_cdc/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $mem_cdc/M_AXI] [get_bd_intf_pins $axi_ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $acq/M_AXI] [get_bd_intf_pins $axi_ic/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins $axi_ic/M00_AXI] [get_bd_intf_pins $mig/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $xdma/M_AXI_LITE] [get_bd_intf_pins $ctrl_cdc/S_AXI]
connect_bd_intf_net [get_bd_intf_pins $ctrl_cdc/M_AXI] [get_bd_intf_pins $acq/S_AXI]

assign_bd_address
validate_bd_design
save_bd_design
set wrapper [make_wrapper -files [get_files system.bd] -top]
add_files -norecurse $wrapper
set_property top system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
generate_target all [get_files system.bd]
puts "Created AX7103 acquisition project: $build_dir"
