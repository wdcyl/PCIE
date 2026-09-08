`timescale 1ns/1ps
`default_nettype none

module pcie_acq_top #(
    parameter integer FIFO_DEPTH = 64,
    parameter integer ADC_VALID_DIV = 1
) (
    input  logic         pcie_clk_i,
    input  logic         pcie_rst_ni,
    input  logic         adc_clk_i,
    input  logic         adc_rst_ni,
    input  logic [255:0] s_axis_rx_tdata_i,
    input  logic [31:0]  s_axis_rx_tkeep_i,
    input  logic         s_axis_rx_tvalid_i,
    output logic         s_axis_rx_tready_o,
    input  logic         s_axis_rx_tlast_i,
    input  logic         s_axis_rx_bar0_hit_i,
    output logic [255:0] m_axis_tx_tdata_o,
    output logic [31:0]  m_axis_tx_tkeep_o,
    output logic         m_axis_tx_tvalid_o,
    input  logic         m_axis_tx_tready_i,
    output logic         m_axis_tx_tlast_o,
    input  logic [15:0]  completer_id_i,
    input  logic [15:0]  requester_id_i,
    output logic         irq_o,
    output logic [31:0]  status_o,
    output logic [31:0]  captured_count_o,
    output logic [31:0]  dropped_count_o
);
    localparam integer FIFO_LEVEL_W = $clog2(FIFO_DEPTH + 1);

    logic [11:0] bar_addr;
    logic bar_wr_en, bar_rd_en, bar_addr_valid;
    logic [31:0] bar_wr_data, bar_rd_data;
    logic [3:0] bar_wr_strb;
    logic [255:0] cpl_tlp_data, dma_tlp_data;
    logic [31:0] cpl_tlp_keep, dma_tlp_keep;
    logic cpl_tlp_valid, cpl_tlp_ready, dma_tlp_valid, dma_tlp_ready;
    logic [31:0] ep_rx_tlp_count, ep_tx_tlp_count, ep_error_count;
    logic start_pulse, clear_stats_pulse;
    logic [31:0] sample_count_cfg, pattern_cfg, irq_status, irq_enable, irq_set;
    logic [31:0] pattern_sync1_adc, pattern_sync2_adc;
    logic [63:0] dma_addr_cfg;
    logic [15:0] adc_data, fifo_wr_data, fifo_rd_data;
    logic adc_valid, acq_busy, acq_done, acq_overflow, fifo_wr_en, fifo_full;
    logic [31:0] captured_count, dropped_count;
    logic [FIFO_LEVEL_W-1:0] fifo_wr_level, fifo_rd_level;
    logic fifo_wr_overflow, fifo_rd_en, fifo_rd_valid, fifo_empty, fifo_rd_underflow;
    logic dma_busy, dma_done, dma_irq_pending;
    logic [31:0] dma_packets_sent;
    logic [63:0] dma_bytes_sent;
    logic dma_done_d, acq_overflow_d;
    logic [31:0] error_count_d;
    logic control_clear;

    // CONTROL[2:1] remain reserved until a coordinated two-clock FIFO flush
    // is added. Statistics clear is supported and should be issued idle.
    assign control_clear = clear_stats_pulse;

    pcie_tlp_endpoint u_endpoint (
        .clk_i(pcie_clk_i), .rst_ni(pcie_rst_ni), .clear_stats_i(clear_stats_pulse),
        .s_axis_rx_tdata_i(s_axis_rx_tdata_i), .s_axis_rx_tkeep_i(s_axis_rx_tkeep_i),
        .s_axis_rx_tvalid_i(s_axis_rx_tvalid_i), .s_axis_rx_tready_o(s_axis_rx_tready_o),
        .s_axis_rx_tlast_i(s_axis_rx_tlast_i), .s_axis_rx_bar0_hit_i(s_axis_rx_bar0_hit_i),
        .m_axis_tx_tdata_o(cpl_tlp_data), .m_axis_tx_tkeep_o(cpl_tlp_keep),
        .m_axis_tx_tvalid_o(cpl_tlp_valid), .m_axis_tx_tready_i(cpl_tlp_ready),
        .m_axis_tx_tlast_o(), .completer_id_i(completer_id_i),
        .bar_addr_o(bar_addr), .bar_wr_en_o(bar_wr_en), .bar_wr_data_o(bar_wr_data),
        .bar_wr_strb_o(bar_wr_strb), .bar_rd_en_o(bar_rd_en),
        .bar_rd_data_i(bar_rd_data), .bar_addr_valid_i(bar_addr_valid),
        .rx_tlp_count_o(ep_rx_tlp_count), .tx_tlp_count_o(ep_tx_tlp_count),
        .error_count_o(ep_error_count)
    );

    bar_registers u_bar (
        .clk_i(pcie_clk_i), .rst_ni(pcie_rst_ni), .addr_i(bar_addr),
        .wr_en_i(bar_wr_en), .wr_data_i(bar_wr_data), .wr_strb_i(bar_wr_strb),
        .rd_en_i(bar_rd_en), .rd_data_o(bar_rd_data), .addr_valid_o(bar_addr_valid),
        .status_i(status_o), .irq_set_i(irq_set), .rx_tlp_count_i(ep_rx_tlp_count),
        .tx_tlp_count_i(ep_tx_tlp_count + dma_packets_sent),
        .error_count_i(ep_error_count + dropped_count), .byte_count_i(dma_bytes_sent),
        .start_pulse_o(start_pulse), .clear_stats_pulse_o(clear_stats_pulse),
        .sample_count_o(sample_count_cfg), .pattern_o(pattern_cfg),
        .dma_addr_o(dma_addr_cfg), .irq_status_o(irq_status),
        .irq_enable_o(irq_enable), .irq_o(irq_o)
    );

    // PATTERN is bundled configuration data: software keeps it stable before
    // START and throughout a capture; two ADC-clock stages prevent bit-level
    // metastability from reaching the pattern generator.
    always_ff @(posedge adc_clk_i or negedge adc_rst_ni) begin
        if (!adc_rst_ni) begin
            pattern_sync1_adc <= 32'd0;
            pattern_sync2_adc <= 32'd0;
        end else begin
            pattern_sync1_adc <= pattern_cfg;
            pattern_sync2_adc <= pattern_sync1_adc;
        end
    end

    adc_pattern_source #(.VALID_DIV(ADC_VALID_DIV)) u_adc_source (
        .adc_clk(adc_clk_i), .adc_rst_n(adc_rst_ni), .enable(1'b1), .restart(1'b0),
        .pattern_sel(pattern_sync2_adc[1:0]),
        .constant_value(pattern_sync2_adc[31:16]),
        .sample_data(adc_data), .sample_valid(adc_valid)
    );

    acquisition_controller u_acquisition (
        .pcie_clk(pcie_clk_i), .pcie_rst_n(pcie_rst_ni), .start(start_pulse),
        .clear_status(control_clear), .sample_count_cfg(sample_count_cfg),
        .busy(acq_busy), .done(acq_done), .overflow(acq_overflow),
        .captured_count(captured_count), .dropped_count(dropped_count),
        .adc_clk(adc_clk_i), .adc_rst_n(adc_rst_ni), .adc_data(adc_data),
        .adc_valid(adc_valid), .fifo_full(fifo_full), .fifo_wr_en(fifo_wr_en),
        .fifo_wr_data(fifo_wr_data)
    );

    async_fifo #(.WIDTH(16), .DEPTH(FIFO_DEPTH)) u_sample_fifo (
        .wr_clk(adc_clk_i), .wr_rst_n(adc_rst_ni), .wr_en(fifo_wr_en),
        .wr_data(fifo_wr_data), .wr_full(fifo_full), .wr_level(fifo_wr_level),
        .wr_overflow(fifo_wr_overflow), .rd_clk(pcie_clk_i), .rd_rst_n(pcie_rst_ni),
        .rd_en(fifo_rd_en), .rd_data(fifo_rd_data), .rd_valid(fifo_rd_valid),
        .rd_empty(fifo_empty), .rd_level(fifo_rd_level), .rd_underflow(fifo_rd_underflow)
    );

    c2h_dma_engine u_dma (
        .pcie_clk(pcie_clk_i), .rst(!pcie_rst_ni), .start(start_pulse),
        .clear(control_clear), .host_addr(dma_addr_cfg), .sample_count(sample_count_cfg),
        .requester_id(requester_id_i), .fifo_rd_data(fifo_rd_data),
        .fifo_empty(fifo_empty), .fifo_rd_valid(fifo_rd_valid), .fifo_rd_en(fifo_rd_en),
        .tlp_data(dma_tlp_data), .tlp_keep(dma_tlp_keep), .tlp_valid(dma_tlp_valid),
        .tlp_ready(dma_tlp_ready), .busy(dma_busy), .done(dma_done),
        .irq_pending(dma_irq_pending), .packets_sent(dma_packets_sent),
        .bytes_sent(dma_bytes_sent)
    );

    tlp_tx_arbiter u_tx_arbiter (
        .clk_i(pcie_clk_i), .rst_ni(pcie_rst_ni),
        .cpl_data_i(cpl_tlp_data), .cpl_keep_i(cpl_tlp_keep),
        .cpl_valid_i(cpl_tlp_valid), .cpl_ready_o(cpl_tlp_ready),
        .dma_data_i(dma_tlp_data), .dma_keep_i(dma_tlp_keep),
        .dma_valid_i(dma_tlp_valid), .dma_ready_o(dma_tlp_ready),
        .tx_data_o(m_axis_tx_tdata_o), .tx_keep_o(m_axis_tx_tkeep_o),
        .tx_valid_o(m_axis_tx_tvalid_o), .tx_ready_i(m_axis_tx_tready_i),
        .tx_last_o(m_axis_tx_tlast_o)
    );

    always_ff @(posedge pcie_clk_i or negedge pcie_rst_ni) begin
        if (!pcie_rst_ni) begin
            dma_done_d <= 1'b0;
            acq_overflow_d <= 1'b0;
            error_count_d <= 32'd0;
        end else begin
            dma_done_d <= dma_done;
            acq_overflow_d <= acq_overflow;
            // Endpoint clears its counter on this same edge. Mirror the
            // cleared value immediately so the falling count is not mistaken
            // for a new protocol-error event on the following cycle.
            if (clear_stats_pulse)
                error_count_d <= 32'd0;
            else
                error_count_d <= ep_error_count;
        end
    end

    always_comb begin
        irq_set = 32'd0;
        irq_set[0] = dma_done & ~dma_done_d;
        irq_set[1] = acq_overflow & ~acq_overflow_d;
        irq_set[2] = (ep_error_count != error_count_d);
    end

    always_comb begin
        status_o = 32'd0;
        status_o[0] = acq_busy;
        status_o[1] = acq_done;
        status_o[2] = acq_overflow;
        status_o[3] = dma_busy;
        status_o[4] = dma_done;
        status_o[5] = fifo_empty;
        status_o[6] = fifo_full;
        status_o[7] = irq_o;
        status_o[23:16] = fifo_rd_level;
    end

    assign captured_count_o = captured_count;
    assign dropped_count_o = dropped_count;
endmodule

`default_nettype wire
