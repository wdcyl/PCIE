`timescale 1ns/1ps
`default_nettype none

// Simulation-only model of the differential MGT reference-clock primitive.
// Vivado uses the device primitive; this file is never added to the project.
module IBUFDS_GTE2 (
    input  wire I,
    input  wire IB,
    input  wire CEB,
    output wire O,
    output wire ODIV2
);
    assign O = I;
    assign ODIV2 = I;
endmodule

// Elaboration-only boundary model for the generated Vivado pcie_7x_0 IP.
// It intentionally models no PCIe protocol behavior. Its sole purpose is to
// catch board-top port-name, direction and width mistakes in open-source CI.
module pcie_7x_0 (
    input  wire [3:0]  pci_exp_rxp,
    input  wire [3:0]  pci_exp_rxn,
    output wire [3:0]  pci_exp_txp,
    output wire [3:0]  pci_exp_txn,
    output wire        user_clk_out,
    output wire        user_reset_out,
    output wire        user_lnk_up,
    output wire        user_app_rdy,
    output wire [5:0]  tx_buf_av,
    output wire        tx_cfg_req,
    output wire        tx_err_drop,
    output wire        s_axis_tx_tready,
    input  wire [63:0] s_axis_tx_tdata,
    input  wire [7:0]  s_axis_tx_tkeep,
    input  wire        s_axis_tx_tlast,
    input  wire        s_axis_tx_tvalid,
    input  wire [3:0]  s_axis_tx_tuser,
    input  wire        tx_cfg_gnt,
    output wire [63:0] m_axis_rx_tdata,
    output wire [7:0]  m_axis_rx_tkeep,
    output wire        m_axis_rx_tlast,
    output wire        m_axis_rx_tvalid,
    input  wire        m_axis_rx_tready,
    output wire [21:0] m_axis_rx_tuser,
    input  wire        rx_np_ok,
    input  wire        rx_np_req,
    input  wire [31:0] cfg_mgmt_di,
    input  wire [3:0]  cfg_mgmt_byte_en,
    input  wire [9:0]  cfg_mgmt_dwaddr,
    input  wire        cfg_mgmt_wr_en,
    input  wire        cfg_mgmt_rd_en,
    input  wire        cfg_mgmt_wr_readonly,
    input  wire        cfg_mgmt_wr_rw1c_as_rw,
    input  wire        cfg_trn_pending,
    input  wire        cfg_pm_halt_aspm_l0s,
    input  wire        cfg_pm_halt_aspm_l1,
    input  wire        cfg_pm_force_state_en,
    input  wire [1:0]  cfg_pm_force_state,
    input  wire [63:0] cfg_dsn,
    input  wire        cfg_interrupt,
    output wire        cfg_interrupt_rdy,
    input  wire        cfg_interrupt_assert,
    input  wire [7:0]  cfg_interrupt_di,
    output wire [7:0]  cfg_interrupt_do,
    output wire [2:0]  cfg_interrupt_mmenable,
    output wire        cfg_interrupt_msienable,
    output wire        cfg_interrupt_msixenable,
    output wire        cfg_interrupt_msixfm,
    input  wire        cfg_interrupt_stat,
    input  wire [4:0]  cfg_pciecap_interrupt_msgnum,
    output wire        cfg_to_turnoff,
    input  wire        cfg_turnoff_ok,
    output wire [7:0]  cfg_bus_number,
    output wire [4:0]  cfg_device_number,
    output wire [2:0]  cfg_function_number,
    input  wire        cfg_pm_wake,
    input  wire        cfg_pm_send_pme_to,
    input  wire [7:0]  cfg_ds_bus_number,
    input  wire [4:0]  cfg_ds_device_number,
    input  wire [2:0]  cfg_ds_function_number,
    input  wire [1:0]  pl_directed_link_change,
    input  wire [1:0]  pl_directed_link_width,
    input  wire        pl_directed_link_speed,
    input  wire        pl_directed_link_auton,
    input  wire        pl_upstream_prefer_deemph,
    input  wire        pl_transmit_hot_rst,
    input  wire        pl_downstream_deemph_source,
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    input  wire        pcie_drp_clk,
    input  wire        pcie_drp_en,
    input  wire        pcie_drp_we,
    input  wire [8:0]  pcie_drp_addr,
    input  wire [15:0] pcie_drp_di,
    output wire [15:0] pcie_drp_do,
    output wire        pcie_drp_rdy,
    output wire [15:0] cfg_command
);

    assign pci_exp_txp = 4'd0;
    assign pci_exp_txn = 4'd0;
    assign user_clk_out = sys_clk;
    assign user_reset_out = !sys_rst_n;
    assign user_lnk_up = 1'b0;
    assign user_app_rdy = 1'b0;
    assign tx_buf_av = 6'd0;
    assign tx_cfg_req = 1'b0;
    assign tx_err_drop = 1'b0;
    assign s_axis_tx_tready = 1'b0;
    assign m_axis_rx_tdata = 64'd0;
    assign m_axis_rx_tkeep = 8'd0;
    assign m_axis_rx_tlast = 1'b0;
    assign m_axis_rx_tvalid = 1'b0;
    assign m_axis_rx_tuser = 22'd0;
    assign cfg_interrupt_rdy = 1'b0;
    assign cfg_interrupt_do = 8'd0;
    assign cfg_interrupt_mmenable = 3'd0;
    assign cfg_interrupt_msienable = 1'b0;
    assign cfg_interrupt_msixenable = 1'b0;
    assign cfg_interrupt_msixfm = 1'b0;
    assign cfg_to_turnoff = 1'b0;
    assign cfg_bus_number = 8'd0;
    assign cfg_device_number = 5'd0;
    assign cfg_function_number = 3'd0;
    assign pcie_drp_do = 16'd0;
    assign pcie_drp_rdy = 1'b0;
    assign cfg_command = 16'd0;

endmodule

`default_nettype wire
