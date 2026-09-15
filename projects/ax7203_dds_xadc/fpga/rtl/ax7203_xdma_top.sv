`timescale 1ns/1ps
`default_nettype none

module ax7203_xdma_top (
    input wire [3:0] pci_exp_rxp, input wire [3:0] pci_exp_rxn,
    output wire [3:0] pci_exp_txp, output wire [3:0] pci_exp_txn,
    input wire sys_clk_p, input wire sys_clk_n, input wire sys_rst_n,
    input wire xadc_vp, input wire xadc_vn,
    output wire dds_sclk, output wire dds_fsync_n, output wire dds_sdata,
    output wire [3:0] led
);
    wire sys_clk, sys_clk_gt;
    IBUFDS_GTE2 u_pcie_refclk (
        .I(sys_clk_p), .IB(sys_clk_n), .CEB(1'b0), .O(sys_clk_gt), .ODIV2(sys_clk)
    );
    xdma_subsystem u_subsystem (
        .sys_clk_i(sys_clk), .sys_clk_gt_i(sys_clk_gt), .sys_rst_ni(sys_rst_n),
        .pci_exp_rxp_i(pci_exp_rxp), .pci_exp_rxn_i(pci_exp_rxn),
        .pci_exp_txp_o(pci_exp_txp), .pci_exp_txn_o(pci_exp_txn),
        .xadc_vp_i(xadc_vp), .xadc_vn_i(xadc_vn),
        .dds_sclk_o(dds_sclk), .dds_fsync_no(dds_fsync_n),
        .dds_sdata_o(dds_sdata), .debug_o(led)
    );
endmodule
`default_nettype wire
