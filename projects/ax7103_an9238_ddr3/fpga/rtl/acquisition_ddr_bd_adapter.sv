`timescale 1ns/1ps
`default_nettype none
module acquisition_ddr_bd_adapter (
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ctrl_clk, ASSOCIATED_BUSIF S_AXI:M_AXI, ASSOCIATED_RESET ctrl_resetn" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ctrl_clk CLK" *) input wire ctrl_clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ctrl_resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ctrl_resetn RST" *) input wire ctrl_resetn,
    input wire link_up,input wire calib_done,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 adc_clk CLK" *) input wire adc_clk,
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME adc_resetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 adc_resetn RST" *) input wire adc_resetn,
    input wire [11:0] adc_ch0,input wire [11:0] adc_ch1,output wire [3:0] debug,
    output wire dds_sclk,output wire dds_fsync_n,output wire dds_sdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *) input wire [31:0] S_AXI_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire S_AXI_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire S_AXI_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] S_AXI_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] S_AXI_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire S_AXI_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire S_AXI_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output wire [1:0] S_AXI_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output wire S_AXI_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire S_AXI_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [31:0] S_AXI_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire S_AXI_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire S_AXI_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output wire [31:0] S_AXI_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output wire [1:0] S_AXI_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output wire S_AXI_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire S_AXI_rready,

    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, PROTOCOL AXI4, DATA_WIDTH 128, ADDR_WIDTH 32, ID_WIDTH 4, MAX_BURST_LENGTH 64" *)
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWID" *) output wire [3:0] M_AXI_awid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *) output wire [31:0] M_AXI_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *) output wire [7:0] M_AXI_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *) output wire [2:0] M_AXI_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *) output wire [1:0] M_AXI_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLOCK" *) output wire M_AXI_awlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWCACHE" *) output wire [3:0] M_AXI_awcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWPROT" *) output wire [2:0] M_AXI_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWQOS" *) output wire [3:0] M_AXI_awqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *) output wire M_AXI_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *) input wire M_AXI_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *) output wire [127:0] M_AXI_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *) output wire [15:0] M_AXI_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *) output wire M_AXI_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *) output wire M_AXI_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *) input wire M_AXI_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BID" *) input wire [3:0] M_AXI_bid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *) input wire [1:0] M_AXI_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *) input wire M_AXI_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *) output wire M_AXI_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARID" *) output wire [3:0] M_AXI_arid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *) output wire [31:0] M_AXI_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *) output wire [7:0] M_AXI_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *) output wire [2:0] M_AXI_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *) output wire [1:0] M_AXI_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLOCK" *) output wire M_AXI_arlock,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARCACHE" *) output wire [3:0] M_AXI_arcache,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARPROT" *) output wire [2:0] M_AXI_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARQOS" *) output wire [3:0] M_AXI_arqos,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *) output wire M_AXI_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *) input wire M_AXI_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RID" *) input wire [3:0] M_AXI_rid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *) input wire [127:0] M_AXI_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *) input wire [1:0] M_AXI_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *) input wire M_AXI_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *) input wire M_AXI_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *) output wire M_AXI_rready
);
    acquisition_ddr_core u_core(
        .ctrl_clk_i(ctrl_clk),.ctrl_rst_ni(ctrl_resetn),.link_up_i(link_up),.calib_done_i(calib_done),
        .adc_clk_i(adc_clk),.adc_rst_ni(adc_resetn),.adc_ch0_i(adc_ch0),.adc_ch1_i(adc_ch1),
        .dds_sclk_o(dds_sclk),.dds_fsync_no(dds_fsync_n),.dds_sdata_o(dds_sdata),
        .s_axil_awaddr_i(S_AXI_awaddr),.s_axil_awvalid_i(S_AXI_awvalid),.s_axil_awready_o(S_AXI_awready),
        .s_axil_wdata_i(S_AXI_wdata),.s_axil_wstrb_i(S_AXI_wstrb),.s_axil_wvalid_i(S_AXI_wvalid),
        .s_axil_wready_o(S_AXI_wready),.s_axil_bresp_o(S_AXI_bresp),.s_axil_bvalid_o(S_AXI_bvalid),
        .s_axil_bready_i(S_AXI_bready),.s_axil_araddr_i(S_AXI_araddr),.s_axil_arvalid_i(S_AXI_arvalid),
        .s_axil_arready_o(S_AXI_arready),.s_axil_rdata_o(S_AXI_rdata),.s_axil_rresp_o(S_AXI_rresp),
        .s_axil_rvalid_o(S_AXI_rvalid),.s_axil_rready_i(S_AXI_rready),
        .m_axi_awid_o(M_AXI_awid),.m_axi_awaddr_o(M_AXI_awaddr),.m_axi_awlen_o(M_AXI_awlen),
        .m_axi_awsize_o(M_AXI_awsize),.m_axi_awburst_o(M_AXI_awburst),.m_axi_awlock_o(M_AXI_awlock),
        .m_axi_awcache_o(M_AXI_awcache),.m_axi_awprot_o(M_AXI_awprot),.m_axi_awqos_o(M_AXI_awqos),
        .m_axi_awvalid_o(M_AXI_awvalid),.m_axi_awready_i(M_AXI_awready),.m_axi_wdata_o(M_AXI_wdata),
        .m_axi_wstrb_o(M_AXI_wstrb),.m_axi_wlast_o(M_AXI_wlast),.m_axi_wvalid_o(M_AXI_wvalid),
        .m_axi_wready_i(M_AXI_wready),.m_axi_bid_i(M_AXI_bid),.m_axi_bresp_i(M_AXI_bresp),
        .m_axi_bvalid_i(M_AXI_bvalid),.m_axi_bready_o(M_AXI_bready),.debug_o(debug));
    assign M_AXI_arid=0;assign M_AXI_araddr=0;assign M_AXI_arlen=0;assign M_AXI_arsize=3'b100;
    assign M_AXI_arburst=2'b01;assign M_AXI_arlock=0;assign M_AXI_arcache=0;assign M_AXI_arprot=0;
    assign M_AXI_arqos=0;assign M_AXI_arvalid=0;assign M_AXI_rready=1;
    wire _unused=&{1'b0,M_AXI_arready,M_AXI_rid,M_AXI_rdata,M_AXI_rresp,M_AXI_rlast,M_AXI_rvalid};
endmodule
`default_nettype wire
