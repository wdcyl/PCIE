`timescale 1ns/1ps
`default_nettype none

// Portable application core.  Vendor IP is isolated in fpga/rtl/xdma_subsystem.sv.
module xadc_xdma_core #(
    parameter integer FIFO_DEPTH = 4096
) (
    input wire user_clk_i, input wire user_rst_ni, input wire link_up_i,
    input wire sample_clk_i, input wire sample_rst_ni,
    input wire [11:0] xadc_sample_i, input wire xadc_sample_valid_i,
    input wire xadc_alarm_i,

    input wire [31:0] s_axil_awaddr_i, input wire s_axil_awvalid_i,
    output wire s_axil_awready_o,
    input wire [31:0] s_axil_wdata_i, input wire [3:0] s_axil_wstrb_i,
    input wire s_axil_wvalid_i, output wire s_axil_wready_o,
    output wire [1:0] s_axil_bresp_o, output wire s_axil_bvalid_o,
    input wire s_axil_bready_i,
    input wire [31:0] s_axil_araddr_i, input wire s_axil_arvalid_i,
    output wire s_axil_arready_o, output wire [31:0] s_axil_rdata_o,
    output wire [1:0] s_axil_rresp_o, output wire s_axil_rvalid_o,
    input wire s_axil_rready_i,

    output wire [127:0] m_axis_c2h_tdata_o,
    output wire [15:0] m_axis_c2h_tkeep_o,
    output wire m_axis_c2h_tvalid_o, input wire m_axis_c2h_tready_i,
    output wire m_axis_c2h_tlast_o,
    output wire [27:0] dds_ftw_o, output wire dds_triangle_o,
    output wire dds_apply_pulse_o, input wire dds_busy_i,
    output wire stream_busy_o
);
    wire start_pulse, clear_pulse;
    wire [31:0] transfer_bytes, mode, stress_seed;
    wire [31:0] sample_count = {1'b0,transfer_bytes[31:1]};
    wire capture_busy, capture_done, capture_overflow;
    wire [31:0] captured_samples, dropped_samples;
    wire fifo_wr_en, fifo_full, fifo_valid, fifo_empty, fifo_rd_en;
    wire [15:0] fifo_wr_data, fifo_rd_data;
    wire [$clog2(FIFO_DEPTH+1)-1:0] fifo_wr_level, fifo_rd_level;
    wire fifo_wr_overflow, fifo_rd_underflow;
    wire [127:0] xadc_tdata, stress_tdata;
    wire [15:0] xadc_tkeep, stress_tkeep;
    wire xadc_tvalid, xadc_tlast, xadc_stream_busy, xadc_done;
    wire stress_tvalid, stress_tlast, stress_busy, stress_done;
    wire select_stress = mode[0];
    wire selected_valid = select_stress ? stress_tvalid : xadc_tvalid;
    wire selected_ready = m_axis_c2h_tready_i;
    wire [15:0] selected_keep = select_stress ? stress_tkeep : xadc_tkeep;
    logic [63:0] stream_bytes_q;
    logic [31:0] backpressure_q;

    function automatic [4:0] count_keep(input [15:0] value);
        integer n;
        begin
            count_keep=0;
            for (n=0;n<16;n=n+1) count_keep=count_keep+value[n];
        end
    endfunction

    wire [31:0] status = {
        22'd0, select_stress, xadc_alarm_i, dds_busy_i, fifo_full,
        fifo_empty, capture_overflow, capture_done,
        stream_busy_o, link_up_i
    };

    axil_control_regs u_regs (
        .clk_i(user_clk_i), .rst_ni(user_rst_ni),
        .s_axil_awaddr_i(s_axil_awaddr_i), .s_axil_awvalid_i(s_axil_awvalid_i),
        .s_axil_awready_o(s_axil_awready_o), .s_axil_wdata_i(s_axil_wdata_i),
        .s_axil_wstrb_i(s_axil_wstrb_i), .s_axil_wvalid_i(s_axil_wvalid_i),
        .s_axil_wready_o(s_axil_wready_o), .s_axil_bresp_o(s_axil_bresp_o),
        .s_axil_bvalid_o(s_axil_bvalid_o), .s_axil_bready_i(s_axil_bready_i),
        .s_axil_araddr_i(s_axil_araddr_i), .s_axil_arvalid_i(s_axil_arvalid_i),
        .s_axil_arready_o(s_axil_arready_o), .s_axil_rdata_o(s_axil_rdata_o),
        .s_axil_rresp_o(s_axil_rresp_o), .s_axil_rvalid_o(s_axil_rvalid_o),
        .s_axil_rready_i(s_axil_rready_i), .status_i(status),
        .stream_bytes_i(stream_bytes_q), .captured_samples_i(captured_samples),
        .dropped_samples_i(dropped_samples), .backpressure_cycles_i(backpressure_q),
        .start_pulse_o(start_pulse), .clear_pulse_o(clear_pulse),
        .dds_apply_pulse_o(dds_apply_pulse_o), .transfer_bytes_o(transfer_bytes),
        .mode_o(mode), .stress_seed_o(stress_seed), .dds_ftw_o(dds_ftw_o),
        .dds_triangle_o(dds_triangle_o)
    );

    xadc_acquisition_controller u_capture (
        .user_clk_i(user_clk_i), .user_rst_ni(user_rst_ni),
        .start_i(start_pulse && !select_stress), .clear_i(clear_pulse),
        .sample_count_i(sample_count), .busy_o(capture_busy),
        .done_o(capture_done), .overflow_o(capture_overflow),
        .captured_count_o(captured_samples), .dropped_count_o(dropped_samples),
        .sample_clk_i(sample_clk_i), .sample_rst_ni(sample_rst_ni),
        .sample_i(xadc_sample_i), .sample_valid_i(xadc_sample_valid_i),
        .fifo_full_i(fifo_full), .fifo_wr_en_o(fifo_wr_en),
        .fifo_wr_data_o(fifo_wr_data)
    );

    async_fifo #(.WIDTH(16),.DEPTH(FIFO_DEPTH)) u_sample_fifo (
        .wr_clk(sample_clk_i), .wr_rst_n(sample_rst_ni), .wr_en(fifo_wr_en),
        .wr_data(fifo_wr_data), .wr_full(fifo_full), .wr_level(fifo_wr_level),
        .wr_overflow(fifo_wr_overflow), .rd_clk(user_clk_i),
        .rd_rst_n(user_rst_ni), .rd_en(fifo_rd_en), .rd_data(fifo_rd_data),
        .rd_valid(fifo_valid), .rd_empty(fifo_empty), .rd_level(fifo_rd_level),
        .rd_underflow(fifo_rd_underflow)
    );

    xadc_axis_packer u_xadc_stream (
        .clk_i(user_clk_i), .rst_ni(user_rst_ni),
        .start_i(start_pulse && !select_stress), .clear_i(clear_pulse),
        .sample_count_i(sample_count), .fifo_data_i(fifo_rd_data),
        .fifo_valid_i(fifo_valid), .fifo_empty_i(fifo_empty),
        .fifo_rd_en_o(fifo_rd_en), .m_axis_tdata_o(xadc_tdata),
        .m_axis_tkeep_o(xadc_tkeep), .m_axis_tvalid_o(xadc_tvalid),
        .m_axis_tready_i(m_axis_c2h_tready_i && !select_stress),
        .m_axis_tlast_o(xadc_tlast), .busy_o(xadc_stream_busy),
        .done_pulse_o(xadc_done)
    );

    axis_stress_source u_stress (
        .clk_i(user_clk_i), .rst_ni(user_rst_ni),
        .start_i(start_pulse && select_stress), .clear_i(clear_pulse),
        .transfer_bytes_i(transfer_bytes), .pattern_i(mode[2:1]),
        .seed_i(stress_seed), .m_axis_tdata_o(stress_tdata),
        .m_axis_tkeep_o(stress_tkeep), .m_axis_tvalid_o(stress_tvalid),
        .m_axis_tready_i(m_axis_c2h_tready_i && select_stress),
        .m_axis_tlast_o(stress_tlast), .busy_o(stress_busy),
        .done_pulse_o(stress_done)
    );

    assign m_axis_c2h_tdata_o = select_stress ? stress_tdata : xadc_tdata;
    assign m_axis_c2h_tkeep_o = selected_keep;
    assign m_axis_c2h_tvalid_o = selected_valid;
    assign m_axis_c2h_tlast_o = select_stress ? stress_tlast : xadc_tlast;
    assign stream_busy_o = select_stress ? stress_busy : xadc_stream_busy;

    always_ff @(posedge user_clk_i or negedge user_rst_ni) begin
        if (!user_rst_ni) begin stream_bytes_q<=0; backpressure_q<=0; end
        else if (clear_pulse) begin stream_bytes_q<=0; backpressure_q<=0; end
        else begin
            if (selected_valid && selected_ready)
                stream_bytes_q<=stream_bytes_q+count_keep(selected_keep);
            if (selected_valid && !selected_ready && backpressure_q!=32'hffff_ffff)
                backpressure_q<=backpressure_q+1'b1;
        end
    end

    wire _unused = &{1'b0,capture_busy,xadc_done,stress_done,
        fifo_wr_level,fifo_rd_level,fifo_wr_overflow,fifo_rd_underflow};
endmodule
`default_nettype wire
