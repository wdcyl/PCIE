// Simulation-only declarations for syntax/elaboration checks without Vivado.
module IBUFDS_GTE2(input I,input IB,input CEB,output O,output ODIV2);
assign O=I; assign ODIV2=1'b0; endmodule

module XADC #(parameter [15:0] INIT_40=0,INIT_41=0,INIT_42=0,INIT_48=0,
 INIT_49=0,INIT_4A=0,INIT_4B=0,INIT_4C=0,INIT_4D=0,INIT_4E=0,INIT_4F=0,
 parameter SIM_DEVICE="7SERIES")(
 input DCLK,RESET,DEN,DWE,input [6:0] DADDR,input [15:0] DI,
 output [15:0] DO,output DRDY,EOC,EOS,output [4:0] CHANNEL,output BUSY,
 output [7:0] ALM,output OT,input VP,VN,input [15:0] VAUXP,VAUXN,
 input CONVST,CONVSTCLK,output JTAGBUSY,JTAGLOCKED,JTAGMODIFIED,MUXADDR);
assign DO=0;assign DRDY=0;assign EOC=0;assign EOS=0;assign CHANNEL=0;
assign BUSY=0;assign ALM=0;assign OT=0;assign JTAGBUSY=0;assign JTAGLOCKED=0;
assign JTAGMODIFIED=0;assign MUXADDR=0; endmodule

module xdma_0(
 input sys_clk,sys_clk_gt,sys_rst_n,input [3:0] pci_exp_rxp,pci_exp_rxn,
 output [3:0] pci_exp_txp,pci_exp_txn,output axi_aclk,axi_aresetn,user_lnk_up,
 input [127:0] s_axis_c2h_tdata_0,input [15:0] s_axis_c2h_tkeep_0,
 input s_axis_c2h_tvalid_0,s_axis_c2h_tlast_0,input [15:0] s_axis_c2h_tuser_0,
 output s_axis_c2h_tready_0,output [127:0] m_axis_h2c_tdata_0,
 output [15:0] m_axis_h2c_tkeep_0,output m_axis_h2c_tvalid_0,m_axis_h2c_tlast_0,
 input m_axis_h2c_tready_0,output [31:0] m_axil_awaddr,output [2:0] m_axil_awprot,
 output m_axil_awvalid,input m_axil_awready,output [31:0] m_axil_wdata,
 output [3:0] m_axil_wstrb,output m_axil_wvalid,input m_axil_wready,
 input [1:0] m_axil_bresp,input m_axil_bvalid,output m_axil_bready,
 output [31:0] m_axil_araddr,output [2:0] m_axil_arprot,output m_axil_arvalid,
 input m_axil_arready,input [31:0] m_axil_rdata,input [1:0] m_axil_rresp,
 input m_axil_rvalid,output m_axil_rready,input usr_irq_req,output usr_irq_ack,
 output msi_enable,output [2:0] msi_vector_width);
assign pci_exp_txp=0;assign pci_exp_txn=0;assign axi_aclk=sys_clk;
assign axi_aresetn=sys_rst_n;assign user_lnk_up=1;assign s_axis_c2h_tready_0=1;
assign m_axis_h2c_tdata_0=0;assign m_axis_h2c_tkeep_0=0;
assign m_axis_h2c_tvalid_0=0;assign m_axis_h2c_tlast_0=0;
assign m_axil_awaddr=0;assign m_axil_awprot=0;assign m_axil_awvalid=0;
assign m_axil_wdata=0;assign m_axil_wstrb=0;assign m_axil_wvalid=0;
assign m_axil_bready=1;assign m_axil_araddr=0;assign m_axil_arprot=0;
assign m_axil_arvalid=0;assign m_axil_rready=1;assign usr_irq_ack=0;
assign msi_enable=0;assign msi_vector_width=0; endmodule
