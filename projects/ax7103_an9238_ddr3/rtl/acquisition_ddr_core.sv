`timescale 1ns/1ps
`default_nettype none
module acquisition_ddr_core #(parameter integer FIFO_DEPTH=1024) (
    input wire ctrl_clk_i,input wire ctrl_rst_ni,input wire link_up_i,input wire calib_done_i,
    input wire adc_clk_i,input wire adc_rst_ni,input wire [11:0] adc_ch0_i,input wire [11:0] adc_ch1_i,
    input wire [31:0] s_axil_awaddr_i,input wire s_axil_awvalid_i,output wire s_axil_awready_o,
    input wire [31:0] s_axil_wdata_i,input wire [3:0] s_axil_wstrb_i,input wire s_axil_wvalid_i,output wire s_axil_wready_o,
    output wire [1:0] s_axil_bresp_o,output wire s_axil_bvalid_o,input wire s_axil_bready_i,
    input wire [31:0] s_axil_araddr_i,input wire s_axil_arvalid_i,output wire s_axil_arready_o,
    output wire [31:0] s_axil_rdata_o,output wire [1:0] s_axil_rresp_o,output wire s_axil_rvalid_o,input wire s_axil_rready_i,
    output wire [3:0] m_axi_awid_o,output wire [31:0] m_axi_awaddr_o,output wire [7:0] m_axi_awlen_o,
    output wire [2:0] m_axi_awsize_o,output wire [1:0] m_axi_awburst_o,output wire m_axi_awlock_o,
    output wire [3:0] m_axi_awcache_o,output wire [2:0] m_axi_awprot_o,output wire [3:0] m_axi_awqos_o,
    output wire m_axi_awvalid_o,input wire m_axi_awready_i,
    output wire [127:0] m_axi_wdata_o,output wire [15:0] m_axi_wstrb_o,output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,input wire m_axi_wready_i,input wire [3:0] m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,input wire m_axi_bvalid_i,output wire m_axi_bready_o,
    output wire [3:0] debug_o
);
    wire start_pulse,clear_pulse; wire [31:0] capture_bytes,buffer_base,mode,test_seed;
    wire capture_busy,capture_done,capture_overflow; wire [31:0] captured_pairs;
    wire fifo_wr_en,fifo_full,fifo_valid,fifo_empty,fifo_rd_en;
    wire [127:0] fifo_wr_data,fifo_rd_data,fifo_stream_data,test_data,source_data;
    wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_wr_level,fifo_rd_level;
    wire fifo_wr_overflow,fifo_rd_underflow,fifo_stream_valid,test_valid,source_valid,source_ready;
    wire writer_ready,writer_done,writer_error,test_busy;
    wire select_test=mode[0];
    wire start_accepted=start_pulse&&link_up_i&&calib_done_i&&writer_ready;
    logic done_sticky_q,buffer_ready_q; logic [63:0] bytes_written_q;
    wire write_resp_error=m_axi_bvalid_i&&m_axi_bready_o&&(m_axi_bresp_i!=2'b00);
    wire [31:0] status={22'd0,select_test,buffer_ready_q,writer_error,capture_overflow,
        done_sticky_q,writer_ready,capture_busy,calib_done_i,link_up_i};

    axil_acquisition_regs u_regs(
        .clk_i(ctrl_clk_i),.rst_ni(ctrl_rst_ni),.s_axil_awaddr_i(s_axil_awaddr_i),.s_axil_awvalid_i(s_axil_awvalid_i),
        .s_axil_awready_o(s_axil_awready_o),.s_axil_wdata_i(s_axil_wdata_i),.s_axil_wstrb_i(s_axil_wstrb_i),
        .s_axil_wvalid_i(s_axil_wvalid_i),.s_axil_wready_o(s_axil_wready_o),.s_axil_bresp_o(s_axil_bresp_o),
        .s_axil_bvalid_o(s_axil_bvalid_o),.s_axil_bready_i(s_axil_bready_i),.s_axil_araddr_i(s_axil_araddr_i),
        .s_axil_arvalid_i(s_axil_arvalid_i),.s_axil_arready_o(s_axil_arready_o),.s_axil_rdata_o(s_axil_rdata_o),
        .s_axil_rresp_o(s_axil_rresp_o),.s_axil_rvalid_o(s_axil_rvalid_o),.s_axil_rready_i(s_axil_rready_i),
        .status_i(status),.captured_pairs_i(select_test?bytes_written_q[33:2]:captured_pairs),.bytes_written_i(bytes_written_q),
        .start_pulse_o(start_pulse),.clear_pulse_o(clear_pulse),.capture_bytes_o(capture_bytes),
        .buffer_base_o(buffer_base),.mode_o(mode),.test_seed_o(test_seed));

    an9238_capture u_capture(
        .ctrl_clk_i(ctrl_clk_i),.ctrl_rst_ni(ctrl_rst_ni),.start_i(start_accepted&&!select_test),.clear_i(clear_pulse),
        .sample_pairs_i(capture_bytes>>2),.busy_o(capture_busy),.done_o(capture_done),.overflow_o(capture_overflow),
        .captured_pairs_o(captured_pairs),.adc_clk_i(adc_clk_i),.adc_rst_ni(adc_rst_ni),.adc_ch0_i(adc_ch0_i),
        .adc_ch1_i(adc_ch1_i),.fifo_wr_en_o(fifo_wr_en),.fifo_wr_data_o(fifo_wr_data),.fifo_full_i(fifo_full));

    async_fifo #(.WIDTH(128),.DEPTH(FIFO_DEPTH)) u_fifo(
        .wr_clk(adc_clk_i),.wr_rst_n(adc_rst_ni),.wr_en(fifo_wr_en),.wr_data(fifo_wr_data),.wr_full(fifo_full),
        .wr_level(fifo_wr_level),.wr_overflow(fifo_wr_overflow),.rd_clk(ctrl_clk_i),.rd_rst_n(ctrl_rst_ni),
        .rd_en(fifo_rd_en),.rd_data(fifo_rd_data),.rd_valid(fifo_valid),.rd_empty(fifo_empty),
        .rd_level(fifo_rd_level),.rd_underflow(fifo_rd_underflow));

    fifo_stream_adapter u_fifo_adapter(
        .clk_i(ctrl_clk_i),.rst_ni(ctrl_rst_ni),.clear_i(clear_pulse||start_accepted),.fifo_data_i(fifo_rd_data),
        .fifo_valid_i(fifo_valid),.fifo_empty_i(fifo_empty),.fifo_rd_en_o(fifo_rd_en),.data_o(fifo_stream_data),
        .valid_o(fifo_stream_valid),.ready_i(source_ready&&!select_test));

    axi_test_source u_test(
        .clk_i(ctrl_clk_i),.rst_ni(ctrl_rst_ni),.start_i(start_accepted&&select_test),.clear_i(clear_pulse),
        .transfer_bytes_i(capture_bytes),.seed_i(test_seed),.data_o(test_data),.valid_o(test_valid),
        .ready_i(source_ready&&select_test),.busy_o(test_busy));
    assign source_data=select_test?test_data:fifo_stream_data;
    assign source_valid=select_test?test_valid:fifo_stream_valid;

    axi_burst_writer u_writer(
        .clk_i(ctrl_clk_i),.rst_ni(ctrl_rst_ni),.start_i(start_accepted),.clear_i(clear_pulse),
        .abort_i(capture_overflow&&!select_test),.base_addr_i(buffer_base),.transfer_bytes_i(capture_bytes),
        .ready_o(writer_ready),.done_pulse_o(writer_done),.error_o(writer_error),.s_data_i(source_data),
        .s_valid_i(source_valid),.s_ready_o(source_ready),.m_axi_awid_o(m_axi_awid_o),.m_axi_awaddr_o(m_axi_awaddr_o),
        .m_axi_awlen_o(m_axi_awlen_o),.m_axi_awsize_o(m_axi_awsize_o),.m_axi_awburst_o(m_axi_awburst_o),
        .m_axi_awlock_o(m_axi_awlock_o),.m_axi_awcache_o(m_axi_awcache_o),.m_axi_awprot_o(m_axi_awprot_o),
        .m_axi_awqos_o(m_axi_awqos_o),.m_axi_awvalid_o(m_axi_awvalid_o),.m_axi_awready_i(m_axi_awready_i),
        .m_axi_wdata_o(m_axi_wdata_o),.m_axi_wstrb_o(m_axi_wstrb_o),.m_axi_wlast_o(m_axi_wlast_o),
        .m_axi_wvalid_o(m_axi_wvalid_o),.m_axi_wready_i(m_axi_wready_i),.m_axi_bid_i(m_axi_bid_i),
        .m_axi_bresp_i(m_axi_bresp_i),.m_axi_bvalid_i(m_axi_bvalid_i),.m_axi_bready_o(m_axi_bready_o));

    always_ff @(posedge ctrl_clk_i or negedge ctrl_rst_ni) begin
        if(!ctrl_rst_ni)begin done_sticky_q<=0;buffer_ready_q<=0;bytes_written_q<=0;end
        else if(clear_pulse||start_accepted)begin done_sticky_q<=0;buffer_ready_q<=0;bytes_written_q<=0;end
        else begin
            if(m_axi_wvalid_o&&m_axi_wready_i)bytes_written_q<=bytes_written_q+16;
            if(writer_done)begin done_sticky_q<=1;buffer_ready_q<=!writer_error&&!write_resp_error&&!capture_overflow;end
        end
    end
    assign debug_o={capture_overflow,buffer_ready_q,calib_done_i,link_up_i};
    wire _unused=&{1'b0,done_sticky_q,test_busy,fifo_wr_level,fifo_rd_level,fifo_wr_overflow,fifo_rd_underflow};
endmodule
`default_nettype wire
