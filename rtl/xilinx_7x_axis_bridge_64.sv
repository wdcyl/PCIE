`timescale 1ns/1ps
`default_nettype none

// Adapter between the 64-bit AXI4-Stream interface of the 7-Series PCIe
// Integrated Block and this project's one-packet, 256-bit canonical TLP bus.
//
// PG054 ordering is preserved: the first AXI beat carries DW0 in [31:0] and
// DW1 in [63:32]. No DWORD or byte swap is required.
module xilinx_7x_axis_bridge_64 (
    input  logic         clk_i,
    input  logic         rst_ni,
    input  logic         clear_stats_i,

    // PCIe IP -> user application (RX)
    input  logic [63:0]  m_axis_rx_tdata_i,
    input  logic [7:0]   m_axis_rx_tkeep_i,
    input  logic         m_axis_rx_tvalid_i,
    output logic         m_axis_rx_tready_o,
    input  logic         m_axis_rx_tlast_i,
    input  logic [21:0]  m_axis_rx_tuser_i,
    output logic         rx_np_ok_o,
    output logic         rx_np_req_o,

    // Canonical packet delivered to pcie_acq_top
    output logic [255:0] rx_tlp_data_o,
    output logic [31:0]  rx_tlp_keep_o,
    output logic         rx_tlp_valid_o,
    input  logic         rx_tlp_ready_i,
    output logic         rx_tlp_last_o,
    output logic         rx_tlp_bar0_hit_o,

    // Canonical packet from pcie_acq_top
    input  logic [255:0] tx_tlp_data_i,
    input  logic [31:0]  tx_tlp_keep_i,
    input  logic         tx_tlp_valid_i,
    output logic         tx_tlp_ready_o,

    // User application -> PCIe IP (TX)
    output logic [63:0]  s_axis_tx_tdata_o,
    output logic [7:0]   s_axis_tx_tkeep_o,
    output logic         s_axis_tx_tvalid_o,
    input  logic         s_axis_tx_tready_i,
    output logic         s_axis_tx_tlast_o,
    output logic [3:0]   s_axis_tx_tuser_o,

    output logic [31:0]  rx_drop_count_o,
    output logic [31:0]  tx_format_error_count_o
);

    logic [255:0] rx_data_q;
    logic [31:0]  rx_keep_q;
    logic [1:0]   rx_beat_q;
    logic         rx_bad_q;
    logic         rx_drain_q;
    logic         rx_bar0_q;
    logic         rx_packet_valid_q;
    logic         rx_packet_bar0_q;

    logic [255:0] tx_data_q;
    logic [31:0]  tx_keep_q;
    logic [1:0]   tx_beat_q;
    logic [1:0]   tx_last_beat_q;
    logic         tx_active_q;

    logic rx_fire;
    logic tx_fire;
    logic current_rx_bad;

    function automatic logic canonical_keep_valid(input logic [31:0] keep);
        begin
            case (keep)
                32'h0000_0fff,
                32'h0000_ffff,
                32'h000f_ffff,
                32'h00ff_ffff,
                32'h0fff_ffff,
                32'hffff_ffff: canonical_keep_valid = 1'b1;
                default:       canonical_keep_valid = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [1:0] canonical_last_beat(input logic [31:0] keep);
        begin
            if (|keep[31:24])
                canonical_last_beat = 2'd3;
            else if (|keep[23:16])
                canonical_last_beat = 2'd2;
            else if (|keep[15:8])
                canonical_last_beat = 2'd1;
            else
                canonical_last_beat = 2'd0;
        end
    endfunction

    assign m_axis_rx_tready_o = !rx_packet_valid_q;
    assign rx_np_ok_o          = !rx_packet_valid_q && !rx_drain_q;
    assign rx_np_req_o         = rx_np_ok_o;
    assign rx_fire             = m_axis_rx_tvalid_i && m_axis_rx_tready_o;

    assign rx_tlp_data_o       = rx_data_q;
    assign rx_tlp_keep_o       = rx_keep_q;
    assign rx_tlp_valid_o      = rx_packet_valid_q;
    assign rx_tlp_last_o       = 1'b1;
    assign rx_tlp_bar0_hit_o   = rx_packet_bar0_q;

    // rx_err_fwd applies throughout the packet. rx_ecrc_err is meaningful at
    // EOF. Non-final 64-bit beats must keep all bytes; final beats are 4 or 8B.
    always_comb begin
        current_rx_bad = m_axis_rx_tuser_i[1];
        if (m_axis_rx_tlast_i && m_axis_rx_tuser_i[0])
            current_rx_bad = 1'b1;
        if (!m_axis_rx_tlast_i && (m_axis_rx_tkeep_i != 8'hff))
            current_rx_bad = 1'b1;
        if (m_axis_rx_tlast_i &&
            (m_axis_rx_tkeep_i != 8'h0f) &&
            (m_axis_rx_tkeep_i != 8'hff))
            current_rx_bad = 1'b1;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rx_data_q         <= 256'd0;
            rx_keep_q         <= 32'd0;
            rx_beat_q         <= 2'd0;
            rx_bad_q          <= 1'b0;
            rx_drain_q        <= 1'b0;
            rx_bar0_q         <= 1'b0;
            rx_packet_valid_q <= 1'b0;
            rx_packet_bar0_q  <= 1'b0;
            rx_drop_count_o   <= 32'd0;
        end else begin
            if (rx_packet_valid_q && rx_tlp_ready_i)
                rx_packet_valid_q <= 1'b0;

            if (rx_fire) begin
                if (!rx_drain_q) begin
                    if (rx_beat_q == 2'd0) begin
                        rx_data_q <= {192'd0, m_axis_rx_tdata_i};
                        rx_keep_q <= {24'd0, m_axis_rx_tkeep_i};
                    end else begin
                        rx_data_q[rx_beat_q*64 +: 64] <= m_axis_rx_tdata_i;
                        rx_keep_q[rx_beat_q*8 +: 8]   <= m_axis_rx_tkeep_i;
                    end
                end

                rx_bad_q  <= rx_bad_q || current_rx_bad;
                rx_bar0_q <= rx_bar0_q || m_axis_rx_tuser_i[2];

                if (m_axis_rx_tlast_i) begin
                    // Only BAR0 traffic belongs to this application. The PCIe
                    // core handles configuration space and unclaimed requests.
                    if (!rx_drain_q && !rx_bad_q && !current_rx_bad &&
                        (rx_bar0_q || m_axis_rx_tuser_i[2])) begin
                        rx_packet_valid_q <= 1'b1;
                        rx_packet_bar0_q  <= 1'b1;
                    end else if (rx_drain_q || rx_bad_q || current_rx_bad) begin
                        rx_drop_count_o <= rx_drop_count_o + 1'b1;
                    end
                    rx_beat_q  <= 2'd0;
                    rx_bad_q   <= 1'b0;
                    rx_drain_q <= 1'b0;
                    rx_bar0_q  <= 1'b0;
                end else if (rx_beat_q == 2'd3) begin
                    // Canonical packets are limited to 32 bytes. Drain the
                    // remainder so a long packet cannot be truncated/executed.
                    rx_drain_q <= 1'b1;
                    rx_bad_q   <= 1'b1;
                end else begin
                    rx_beat_q <= rx_beat_q + 1'b1;
                end
            end

            if (clear_stats_i)
                rx_drop_count_o <= 32'd0;
        end
    end

    assign tx_tlp_ready_o       = !tx_active_q;
    assign s_axis_tx_tvalid_o   = tx_active_q;
    assign s_axis_tx_tlast_o    = tx_active_q && (tx_beat_q == tx_last_beat_q);
    assign s_axis_tx_tuser_o    = 4'b0000;
    assign tx_fire              = s_axis_tx_tvalid_o && s_axis_tx_tready_i;

    always_comb begin
        case (tx_beat_q)
            2'd0: begin
                s_axis_tx_tdata_o = tx_data_q[63:0];
                s_axis_tx_tkeep_o = tx_keep_q[7:0];
            end
            2'd1: begin
                s_axis_tx_tdata_o = tx_data_q[127:64];
                s_axis_tx_tkeep_o = tx_keep_q[15:8];
            end
            2'd2: begin
                s_axis_tx_tdata_o = tx_data_q[191:128];
                s_axis_tx_tkeep_o = tx_keep_q[23:16];
            end
            default: begin
                s_axis_tx_tdata_o = tx_data_q[255:192];
                s_axis_tx_tkeep_o = tx_keep_q[31:24];
            end
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tx_data_q                  <= 256'd0;
            tx_keep_q                  <= 32'd0;
            tx_beat_q                  <= 2'd0;
            tx_last_beat_q             <= 2'd0;
            tx_active_q                <= 1'b0;
            tx_format_error_count_o    <= 32'd0;
        end else begin
            if (tx_tlp_valid_i && tx_tlp_ready_o) begin
                if (canonical_keep_valid(tx_tlp_keep_i)) begin
                    tx_data_q      <= tx_tlp_data_i;
                    tx_keep_q      <= tx_tlp_keep_i;
                    tx_beat_q      <= 2'd0;
                    tx_last_beat_q <= canonical_last_beat(tx_tlp_keep_i);
                    tx_active_q    <= 1'b1;
                end else begin
                    tx_format_error_count_o <= tx_format_error_count_o + 1'b1;
                end
            end

            if (tx_fire) begin
                if (tx_beat_q == tx_last_beat_q) begin
                    tx_active_q <= 1'b0;
                    tx_beat_q   <= 2'd0;
                end else begin
                    tx_beat_q <= tx_beat_q + 1'b1;
                end
            end

            if (clear_stats_i)
                tx_format_error_count_o <= 32'd0;
        end
    end

endmodule

`default_nettype wire
