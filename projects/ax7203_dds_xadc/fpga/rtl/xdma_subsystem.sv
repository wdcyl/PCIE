`timescale 1ns/1ps
`default_nettype none

// AX7203 vendor boundary: generated XDMA IP plus reusable application RTL.
module xdma_subsystem #(
    parameter integer FIFO_DEPTH=4096
) (
    input wire sys_clk_i, input wire sys_clk_gt_i, input wire sys_rst_ni,
    input wire [3:0] pci_exp_rxp_i, input wire [3:0] pci_exp_rxn_i,
    output wire [3:0] pci_exp_txp_o, output wire [3:0] pci_exp_txn_o,
    input wire xadc_vp_i, input wire xadc_vn_i,
    output wire dds_sclk_o, output wire dds_fsync_no, output wire dds_sdata_o,
    output wire [3:0] debug_o
);
    wire axi_aclk, axi_aresetn, user_lnk_up;
    wire [31:0] m_axil_awaddr, m_axil_wdata, m_axil_araddr, m_axil_rdata;
    wire [2:0] m_axil_awprot, m_axil_arprot;
    wire [3:0] m_axil_wstrb;
    wire m_axil_awvalid,m_axil_awready,m_axil_wvalid,m_axil_wready;
    wire [1:0] m_axil_bresp,m_axil_rresp;
    wire m_axil_bvalid,m_axil_bready,m_axil_arvalid,m_axil_arready;
    wire m_axil_rvalid,m_axil_rready;
    wire [127:0] c2h_tdata, h2c_tdata;
    wire [15:0] c2h_tkeep, h2c_tkeep;
    wire c2h_tvalid,c2h_tready,c2h_tlast;
    wire h2c_tvalid,h2c_tlast;
    wire [11:0] xadc_sample;
    wire xadc_valid,xadc_alarm,xadc_busy;
    wire [27:0] dds_ftw;
    wire dds_triangle,dds_apply,dds_busy,dds_done,stream_busy;
    wire irq_ack,msi_enable;
    wire [2:0] msi_vector_width;

    xadc_sampler u_sampler (
        .dclk_i(axi_aclk), .rst_ni(axi_aresetn),
        .vp_i(xadc_vp_i), .vn_i(xadc_vn_i), .sample_o(xadc_sample),
        .sample_valid_o(xadc_valid), .alarm_o(xadc_alarm), .busy_o(xadc_busy)
    );

    ad9833_controller #(.CLK_DIV(16)) u_dds (
        .clk_i(axi_aclk), .rst_ni(axi_aresetn), .apply_i(dds_apply),
        .ftw_i(dds_ftw), .triangle_i(dds_triangle), .busy_o(dds_busy),
        .done_pulse_o(dds_done), .sclk_o(dds_sclk_o),
        .fsync_no(dds_fsync_no), .sdata_o(dds_sdata_o)
    );

    xadc_xdma_core #(.FIFO_DEPTH(FIFO_DEPTH)) u_application (
        .user_clk_i(axi_aclk), .user_rst_ni(axi_aresetn), .link_up_i(user_lnk_up),
        .sample_clk_i(axi_aclk), .sample_rst_ni(axi_aresetn),
        .xadc_sample_i(xadc_sample), .xadc_sample_valid_i(xadc_valid),
        .xadc_alarm_i(xadc_alarm),
        .s_axil_awaddr_i(m_axil_awaddr), .s_axil_awvalid_i(m_axil_awvalid),
        .s_axil_awready_o(m_axil_awready), .s_axil_wdata_i(m_axil_wdata),
        .s_axil_wstrb_i(m_axil_wstrb), .s_axil_wvalid_i(m_axil_wvalid),
        .s_axil_wready_o(m_axil_wready), .s_axil_bresp_o(m_axil_bresp),
        .s_axil_bvalid_o(m_axil_bvalid), .s_axil_bready_i(m_axil_bready),
        .s_axil_araddr_i(m_axil_araddr), .s_axil_arvalid_i(m_axil_arvalid),
        .s_axil_arready_o(m_axil_arready), .s_axil_rdata_o(m_axil_rdata),
        .s_axil_rresp_o(m_axil_rresp), .s_axil_rvalid_o(m_axil_rvalid),
        .s_axil_rready_i(m_axil_rready), .m_axis_c2h_tdata_o(c2h_tdata),
        .m_axis_c2h_tkeep_o(c2h_tkeep), .m_axis_c2h_tvalid_o(c2h_tvalid),
        .m_axis_c2h_tready_i(c2h_tready), .m_axis_c2h_tlast_o(c2h_tlast),
        .dds_ftw_o(dds_ftw), .dds_triangle_o(dds_triangle),
        .dds_apply_pulse_o(dds_apply), .dds_busy_i(dds_busy),
        .stream_busy_o(stream_busy)
    );

    xdma_0 u_xdma (
        .sys_clk(sys_clk_i), .sys_clk_gt(sys_clk_gt_i), .sys_rst_n(sys_rst_ni),
        .pci_exp_rxp(pci_exp_rxp_i), .pci_exp_rxn(pci_exp_rxn_i),
        .pci_exp_txp(pci_exp_txp_o), .pci_exp_txn(pci_exp_txn_o),
        .axi_aclk(axi_aclk), .axi_aresetn(axi_aresetn), .user_lnk_up(user_lnk_up),
        .s_axis_c2h_tdata_0(c2h_tdata), .s_axis_c2h_tkeep_0(c2h_tkeep),
        .s_axis_c2h_tvalid_0(c2h_tvalid), .s_axis_c2h_tready_0(c2h_tready),
        .s_axis_c2h_tlast_0(c2h_tlast), .s_axis_c2h_tuser_0(16'd0),
        .m_axis_h2c_tdata_0(h2c_tdata), .m_axis_h2c_tkeep_0(h2c_tkeep),
        .m_axis_h2c_tvalid_0(h2c_tvalid), .m_axis_h2c_tready_0(1'b1),
        .m_axis_h2c_tlast_0(h2c_tlast),
        .m_axil_awaddr(m_axil_awaddr), .m_axil_awprot(m_axil_awprot),
        .m_axil_awvalid(m_axil_awvalid), .m_axil_awready(m_axil_awready),
        .m_axil_wdata(m_axil_wdata), .m_axil_wstrb(m_axil_wstrb),
        .m_axil_wvalid(m_axil_wvalid), .m_axil_wready(m_axil_wready),
        .m_axil_bresp(m_axil_bresp), .m_axil_bvalid(m_axil_bvalid),
        .m_axil_bready(m_axil_bready), .m_axil_araddr(m_axil_araddr),
        .m_axil_arprot(m_axil_arprot), .m_axil_arvalid(m_axil_arvalid),
        .m_axil_arready(m_axil_arready), .m_axil_rdata(m_axil_rdata),
        .m_axil_rresp(m_axil_rresp), .m_axil_rvalid(m_axil_rvalid),
        .m_axil_rready(m_axil_rready), .usr_irq_req(1'b0), .usr_irq_ack(irq_ack),
        .msi_enable(msi_enable), .msi_vector_width(msi_vector_width)
    );

    assign debug_o={xadc_alarm,dds_busy,stream_busy,user_lnk_up};
    wire _unused=&{1'b0,m_axil_awprot,m_axil_arprot,h2c_tdata,h2c_tkeep,
        h2c_tvalid,h2c_tlast,irq_ack,msi_enable,msi_vector_width,dds_done,xadc_busy};
endmodule
`default_nettype wire
