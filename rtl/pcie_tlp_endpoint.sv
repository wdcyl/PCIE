`timescale 1ns/1ps
`default_nettype none
`include "pcie_defs.svh"

// Minimal BAR0 completer for simulation and FPGA-side transaction-layer study.
//
// Stream byte/DW convention:
//   tdata[31:0]   = TLP DW0, tdata[63:32]  = DW1,
//   tdata[95:64]  = TLP DW2, tdata[127:96] = first payload DW.
// tkeep has one bit per byte.  Every accepted packet must be a single beat with
// tlast asserted.  A PCIe hard-IP wrapper may need to reorder bytes/DWs to this
// canonical format.
module pcie_tlp_endpoint (
    input  logic          clk_i,
    input  logic          rst_ni,
    input  logic          clear_stats_i,

    input  logic [255:0]  s_axis_rx_tdata_i,
    input  logic [31:0]   s_axis_rx_tkeep_i,
    input  logic          s_axis_rx_tvalid_i,
    output logic          s_axis_rx_tready_o,
    input  logic          s_axis_rx_tlast_i,
    input  logic          s_axis_rx_bar0_hit_i,

    output logic [255:0]  m_axis_tx_tdata_o,
    output logic [31:0]   m_axis_tx_tkeep_o,
    output logic          m_axis_tx_tvalid_o,
    input  logic          m_axis_tx_tready_i,
    output logic          m_axis_tx_tlast_o,

    input  logic [15:0]   completer_id_i,

    output logic [11:0]   bar_addr_o,
    output logic          bar_wr_en_o,
    output logic [31:0]   bar_wr_data_o,
    output logic [3:0]    bar_wr_strb_o,
    output logic          bar_rd_en_o,
    input  logic [31:0]   bar_rd_data_i,
    input  logic          bar_addr_valid_i,

    output logic [31:0]   rx_tlp_count_o,
    output logic [31:0]   tx_tlp_count_o,
    output logic [31:0]   error_count_o
);

    logic [255:0] tx_data_q;
    logic [31:0]  tx_keep_q;
    logic         tx_valid_q;

    wire [31:0] rx_dw0 = s_axis_rx_tdata_i[31:0];
    wire [31:0] rx_dw1 = s_axis_rx_tdata_i[63:32];
    wire [31:0] rx_dw2 = s_axis_rx_tdata_i[95:64];
    wire [31:0] rx_dw3 = s_axis_rx_tdata_i[127:96];

    wire [7:0]  rx_fmt_type    = rx_dw0[31:24];
    wire [9:0]  rx_length      = rx_dw0[9:0];
    wire [15:0] rx_requester_id= rx_dw1[31:16];
    wire [7:0]  rx_tag         = rx_dw1[15:8];
    wire [3:0]  rx_last_be     = rx_dw1[7:4];
    wire [3:0]  rx_first_be    = rx_dw1[3:0];
    wire [31:0] rx_address     = {rx_dw2[31:2], 2'b00};

    logic [1:0]  first_byte_offset;
    logic [2:0]  enabled_byte_count;
    logic [6:0]  completion_lower_addr;
    logic        rx_fire;
    logic        common_header_ok;
    logic        mrd_supported;
    logic        mwr_supported;
    logic        memory_read_request;
    logic        memory_write_request;

    always_comb begin
        casez (rx_first_be)
            4'b???1: first_byte_offset = 2'd0;
            4'b??10: first_byte_offset = 2'd1;
            4'b?100: first_byte_offset = 2'd2;
            4'b1000: first_byte_offset = 2'd3;
            default: first_byte_offset = 2'd0;
        endcase
    end

    always_comb begin
        enabled_byte_count = {2'b00, rx_first_be[0]} +
                             {2'b00, rx_first_be[1]} +
                             {2'b00, rx_first_be[2]} +
                             {2'b00, rx_first_be[3]};
    end

    assign completion_lower_addr = {rx_address[6:2], first_byte_offset};
    assign common_header_ok = s_axis_rx_tlast_i &&
                              (&s_axis_rx_tkeep_i[11:0]) &&
                              (rx_length == 10'd1) &&
                              (rx_last_be == 4'b0000) &&
                              (rx_first_be != 4'b0000);

    assign mrd_supported = (rx_fmt_type == `PCIE_TLP_MRD32) &&
                           common_header_ok &&
                           s_axis_rx_bar0_hit_i &&
                           bar_addr_valid_i;

    assign mwr_supported = (rx_fmt_type == `PCIE_TLP_MWR32) &&
                           common_header_ok &&
                           (&s_axis_rx_tkeep_i[15:12]) &&
                           s_axis_rx_bar0_hit_i &&
                           bar_addr_valid_i;

    assign memory_read_request = (rx_fmt_type == `PCIE_TLP_MRD32) ||
                                 (rx_fmt_type == `PCIE_TLP_MRD64);
    assign memory_write_request = (rx_fmt_type == `PCIE_TLP_MWR32) ||
                                  (rx_fmt_type == `PCIE_TLP_MWR64);

    // One response may be buffered.  A new RX packet can be accepted on the
    // same edge that the previous response is consumed.
    assign s_axis_rx_tready_o = !tx_valid_q || m_axis_tx_tready_i;
    assign rx_fire             = s_axis_rx_tvalid_i && s_axis_rx_tready_o;

    assign bar_addr_o    = rx_address[11:0];
    assign bar_wr_data_o = rx_dw3;
    assign bar_wr_strb_o = rx_first_be;
    assign bar_wr_en_o   = rx_fire && mwr_supported;
    assign bar_rd_en_o   = rx_fire && (rx_fmt_type == `PCIE_TLP_MRD32) &&
                           common_header_ok && s_axis_rx_bar0_hit_i;

    assign m_axis_tx_tdata_o  = tx_data_q;
    assign m_axis_tx_tkeep_o  = tx_keep_q;
    assign m_axis_tx_tvalid_o = tx_valid_q;
    assign m_axis_tx_tlast_o  = 1'b1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tx_data_q       <= 256'd0;
            tx_keep_q       <= 32'd0;
            tx_valid_q      <= 1'b0;
            rx_tlp_count_o  <= 32'd0;
            tx_tlp_count_o  <= 32'd0;
            error_count_o   <= 32'd0;
        end else begin
            if (tx_valid_q && m_axis_tx_tready_i) begin
                tx_valid_q     <= 1'b0;
                tx_tlp_count_o <= tx_tlp_count_o + 1'b1;
            end

            if (rx_fire) begin
                rx_tlp_count_o <= rx_tlp_count_o + 1'b1;

                if (mrd_supported) begin
                    // Successful Completion with one payload DW.
                    tx_data_q          <= 256'd0;
                    tx_data_q[31:0]    <= {`PCIE_TLP_CPLD, 14'd0, 10'd1};
                    tx_data_q[63:32]   <= {completer_id_i, `PCIE_CPL_SC, 1'b0,
                                           9'd0, enabled_byte_count};
                    tx_data_q[95:64]   <= {rx_requester_id, rx_tag, 1'b0,
                                           completion_lower_addr};
                    tx_data_q[127:96]  <= bar_rd_data_i;
                    tx_keep_q          <= 32'h0000_ffff;
                    tx_valid_q         <= 1'b1;
                end else if (memory_write_request) begin
                    // Both MWr32 and MWr64 are posted and never receive a
                    // Completion. Unsupported/malformed writes are counted.
                    if (!mwr_supported)
                        error_count_o <= error_count_o + 1'b1;
                end else if (memory_read_request) begin
                    // Unsupported/malformed memory read: Completion UR.
                    tx_data_q         <= 256'd0;
                    tx_data_q[31:0]   <= {`PCIE_TLP_CPL, 14'd0, 10'd0};
                    tx_data_q[63:32]  <= {completer_id_i, `PCIE_CPL_UR, 1'b0, 12'd0};
                    tx_data_q[95:64]  <= {rx_requester_id, rx_tag, 8'd0};
                    tx_keep_q         <= 32'h0000_0fff;
                    tx_valid_q        <= 1'b1;
                    error_count_o     <= error_count_o + 1'b1;
                end else begin
                    // Other packet classes are outside this BAR completer.
                    // Never synthesize a Completion for an unknown packet,
                    // because it may itself be Posted or a Completion.
                    error_count_o <= error_count_o + 1'b1;
                end
            end

            if (clear_stats_i) begin
                rx_tlp_count_o <= 32'd0;
                tx_tlp_count_o <= 32'd0;
                error_count_o  <= 32'd0;
            end
        end
    end

endmodule

`default_nettype wire
