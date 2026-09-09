`timescale 1ns/1ps
`default_nettype none

// KC705 board-level integration for one Vivado-generated pcie_7x_0 instance.
// Target configuration: Gen2 x4, 64-bit AXI4-Stream @ 250 MHz, 4 KiB BAR0,
// single-vector MSI with 64-bit address capability.
module kc705_pcie_top (
    input  wire [3:0] pci_exp_rxp,
    input  wire [3:0] pci_exp_rxn,
    output wire [3:0] pci_exp_txp,
    output wire [3:0] pci_exp_txn,
    input  wire       sys_clk_p,
    input  wire       sys_clk_n,
    input  wire       sys_rst_n,
    output wire [3:0] led_o
);

    wire sys_clk;
    wire user_clk;
    wire user_reset;
    wire user_reset_n = ~user_reset;
    wire user_lnk_up;

    IBUFDS_GTE2 u_pcie_refclk (
        .I(sys_clk_p),
        .IB(sys_clk_n),
        .CEB(1'b0),
        .O(sys_clk),
        .ODIV2()
    );

    wire [63:0] ip_rx_data;
    wire [7:0]  ip_rx_keep;
    wire        ip_rx_valid;
    wire        ip_rx_ready;
    wire        ip_rx_last;
    wire [21:0] ip_rx_user;
    wire        rx_np_ok;
    wire        rx_np_req;

    wire [63:0] ip_tx_data;
    wire [7:0]  ip_tx_keep;
    wire        ip_tx_valid;
    wire        ip_tx_ready;
    wire        ip_tx_last;
    wire [3:0]  ip_tx_user;

    wire [255:0] app_rx_data;
    wire [31:0]  app_rx_keep;
    wire         app_rx_valid;
    wire         app_rx_ready;
    wire         app_rx_last;
    wire         app_rx_bar0_hit;
    wire [255:0] app_tx_data;
    wire [31:0]  app_tx_keep;
    wire         app_tx_valid;
    wire         app_tx_ready;
    wire         app_tx_last;

    wire [15:0] cfg_command;
    wire [7:0]  cfg_bus_number;
    wire [4:0]  cfg_device_number;
    wire [2:0]  cfg_function_number;
    wire [15:0] requester_id = {
        cfg_bus_number, cfg_device_number, cfg_function_number
    };
    wire        bus_master_enable = cfg_command[2];
    wire        dma_enable = user_lnk_up && bus_master_enable;

    wire        app_irq_pending;
    wire [31:0] app_status;
    wire [31:0] captured_count;
    wire [31:0] dropped_count;
    wire [31:0] bridge_rx_drop_count;
    wire [31:0] bridge_tx_error_count;

    wire        cfg_interrupt;
    wire        cfg_interrupt_rdy;
    wire        cfg_interrupt_assert;
    wire [7:0]  cfg_interrupt_di;
    wire        cfg_interrupt_stat;
    wire [4:0]  cfg_pciecap_interrupt_msgnum;
    wire        cfg_interrupt_msienable;
    wire [2:0]  cfg_interrupt_mmenable;
    wire        cfg_interrupt_msixenable;
    wire        cfg_interrupt_msixfm;
    wire        msi_request_active;
    wire [31:0] msi_sent_count;

    wire cfg_to_turnoff;
    // Do not acknowledge D3hot/turn-off while application or adapter traffic
    // is still buffered. cfg_trn_pending covers application-generated TLPs;
    // the PCIe core accounts for its own configuration/MSI traffic.
    wire cfg_turnoff_ok = cfg_to_turnoff && !app_status[0] && !app_status[3] &&
                          !app_tx_valid && !ip_tx_valid && !msi_request_active;
    wire cfg_trn_pending = app_status[3] || app_tx_valid || ip_tx_valid;

    xilinx_7x_axis_bridge_64 u_axis_bridge (
        .clk_i(user_clk),
        .rst_ni(user_reset_n),
        .clear_stats_i(1'b0),
        .m_axis_rx_tdata_i(ip_rx_data),
        .m_axis_rx_tkeep_i(ip_rx_keep),
        .m_axis_rx_tvalid_i(ip_rx_valid),
        .m_axis_rx_tready_o(ip_rx_ready),
        .m_axis_rx_tlast_i(ip_rx_last),
        .m_axis_rx_tuser_i(ip_rx_user),
        .rx_np_ok_o(rx_np_ok),
        .rx_np_req_o(rx_np_req),
        .rx_tlp_data_o(app_rx_data),
        .rx_tlp_keep_o(app_rx_keep),
        .rx_tlp_valid_o(app_rx_valid),
        .rx_tlp_ready_i(app_rx_ready),
        .rx_tlp_last_o(app_rx_last),
        .rx_tlp_bar0_hit_o(app_rx_bar0_hit),
        .tx_tlp_data_i(app_tx_data),
        .tx_tlp_keep_i(app_tx_keep),
        .tx_tlp_valid_i(app_tx_valid),
        .tx_tlp_ready_o(app_tx_ready),
        .s_axis_tx_tdata_o(ip_tx_data),
        .s_axis_tx_tkeep_o(ip_tx_keep),
        .s_axis_tx_tvalid_o(ip_tx_valid),
        .s_axis_tx_tready_i(ip_tx_ready),
        .s_axis_tx_tlast_o(ip_tx_last),
        .s_axis_tx_tuser_o(ip_tx_user),
        .rx_drop_count_o(bridge_rx_drop_count),
        .tx_format_error_count_o(bridge_tx_error_count)
    );

    // The internal ADC pattern source uses user_clk on the board build. This
    // requires no extra pins and exercises the complete acquisition/DMA path.
    pcie_acq_top #(
        .FIFO_DEPTH(1024),
        .ADC_VALID_DIV(8)
    ) u_application (
        .pcie_clk_i(user_clk),
        .pcie_rst_ni(user_reset_n),
        .adc_clk_i(user_clk),
        .adc_rst_ni(user_reset_n),
        .s_axis_rx_tdata_i(app_rx_data),
        .s_axis_rx_tkeep_i(app_rx_keep),
        .s_axis_rx_tvalid_i(app_rx_valid),
        .s_axis_rx_tready_o(app_rx_ready),
        .s_axis_rx_tlast_i(app_rx_last),
        .s_axis_rx_bar0_hit_i(app_rx_bar0_hit),
        .m_axis_tx_tdata_o(app_tx_data),
        .m_axis_tx_tkeep_o(app_tx_keep),
        .m_axis_tx_tvalid_o(app_tx_valid),
        .m_axis_tx_tready_i(app_tx_ready),
        .m_axis_tx_tlast_o(app_tx_last),
        .completer_id_i(requester_id),
        .requester_id_i(requester_id),
        .dma_enable_i(dma_enable),
        .irq_o(app_irq_pending),
        .status_o(app_status),
        .captured_count_o(captured_count),
        .dropped_count_o(dropped_count)
    );

    xilinx_7x_msi_controller u_msi_controller (
        .clk_i(user_clk),
        .rst_ni(user_reset_n),
        .link_up_i(user_lnk_up),
        .irq_pending_i(app_irq_pending),
        .cfg_interrupt_msienable_i(cfg_interrupt_msienable),
        .cfg_interrupt_rdy_i(cfg_interrupt_rdy),
        .cfg_interrupt_o(cfg_interrupt),
        .cfg_interrupt_assert_o(cfg_interrupt_assert),
        .cfg_interrupt_di_o(cfg_interrupt_di),
        .cfg_interrupt_stat_o(cfg_interrupt_stat),
        .cfg_pciecap_interrupt_msgnum_o(cfg_pciecap_interrupt_msgnum),
        .request_active_o(msi_request_active),
        .msi_sent_count_o(msi_sent_count)
    );

    // This is the only PCIe hard-IP instance in the project. The module is
    // generated reproducibly by fpga/kc705/tcl/create_project.tcl.
    pcie_7x_0 u_pcie_7x_0 (
        .pci_exp_rxp(pci_exp_rxp),
        .pci_exp_rxn(pci_exp_rxn),
        .pci_exp_txp(pci_exp_txp),
        .pci_exp_txn(pci_exp_txn),
        .user_clk_out(user_clk),
        .user_reset_out(user_reset),
        .user_lnk_up(user_lnk_up),
        .user_app_rdy(),
        .tx_buf_av(),
        .tx_cfg_req(),
        .tx_err_drop(),
        .s_axis_tx_tready(ip_tx_ready),
        .s_axis_tx_tdata(ip_tx_data),
        .s_axis_tx_tkeep(ip_tx_keep),
        .s_axis_tx_tlast(ip_tx_last),
        .s_axis_tx_tvalid(ip_tx_valid),
        .s_axis_tx_tuser(ip_tx_user),
        .tx_cfg_gnt(1'b1),
        .m_axis_rx_tdata(ip_rx_data),
        .m_axis_rx_tkeep(ip_rx_keep),
        .m_axis_rx_tlast(ip_rx_last),
        .m_axis_rx_tvalid(ip_rx_valid),
        .m_axis_rx_tready(ip_rx_ready),
        .m_axis_rx_tuser(ip_rx_user),
        .rx_np_ok(rx_np_ok),
        .rx_np_req(rx_np_req),
        .cfg_mgmt_di(32'd0),
        .cfg_mgmt_byte_en(4'd0),
        .cfg_mgmt_dwaddr(10'd0),
        .cfg_mgmt_wr_en(1'b0),
        .cfg_mgmt_rd_en(1'b0),
        .cfg_mgmt_wr_readonly(1'b0),
        .cfg_mgmt_wr_rw1c_as_rw(1'b0),
        .cfg_trn_pending(cfg_trn_pending),
        .cfg_pm_halt_aspm_l0s(1'b0),
        .cfg_pm_halt_aspm_l1(1'b0),
        .cfg_pm_force_state_en(1'b0),
        .cfg_pm_force_state(2'b00),
        .cfg_dsn(64'h0000_0001_0000_0001),
        .cfg_interrupt(cfg_interrupt),
        .cfg_interrupt_rdy(cfg_interrupt_rdy),
        .cfg_interrupt_assert(cfg_interrupt_assert),
        .cfg_interrupt_di(cfg_interrupt_di),
        .cfg_interrupt_do(),
        .cfg_interrupt_mmenable(cfg_interrupt_mmenable),
        .cfg_interrupt_msienable(cfg_interrupt_msienable),
        .cfg_interrupt_msixenable(cfg_interrupt_msixenable),
        .cfg_interrupt_msixfm(cfg_interrupt_msixfm),
        .cfg_interrupt_stat(cfg_interrupt_stat),
        .cfg_pciecap_interrupt_msgnum(cfg_pciecap_interrupt_msgnum),
        .cfg_to_turnoff(cfg_to_turnoff),
        .cfg_turnoff_ok(cfg_turnoff_ok),
        .cfg_bus_number(cfg_bus_number),
        .cfg_device_number(cfg_device_number),
        .cfg_function_number(cfg_function_number),
        .cfg_pm_wake(1'b0),
        .cfg_pm_send_pme_to(1'b0),
        .cfg_ds_bus_number(8'd0),
        .cfg_ds_device_number(5'd0),
        .cfg_ds_function_number(3'd0),
        .pl_directed_link_change(2'b00),
        .pl_directed_link_width(2'b00),
        .pl_directed_link_speed(1'b0),
        .pl_directed_link_auton(1'b0),
        .pl_upstream_prefer_deemph(1'b1),
        .pl_transmit_hot_rst(1'b0),
        .pl_downstream_deemph_source(1'b0),
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .pcie_drp_clk(user_clk),
        .pcie_drp_en(1'b0),
        .pcie_drp_we(1'b0),
        .pcie_drp_addr(9'd0),
        .pcie_drp_di(16'd0),
        .pcie_drp_do(),
        .pcie_drp_rdy(),
        .cfg_command(cfg_command)
    );

    // KC705 GPIO LEDs are active high.
    assign led_o[0] = user_lnk_up;
    assign led_o[1] = bus_master_enable;
    assign led_o[2] = cfg_interrupt_msienable;
    assign led_o[3] = app_irq_pending || (|bridge_rx_drop_count) ||
                      (|bridge_tx_error_count);

endmodule

`default_nettype wire
