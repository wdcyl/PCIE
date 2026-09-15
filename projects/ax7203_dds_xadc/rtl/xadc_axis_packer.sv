`timescale 1ns/1ps
`default_nettype none

// Packs eight 16-bit XADC samples into a 128-bit XDMA C2H beat.
module xadc_axis_packer (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         start_i,
    input  wire         clear_i,
    input  wire [31:0]  sample_count_i,
    input  wire [15:0]  fifo_data_i,
    input  wire         fifo_valid_i,
    input  wire         fifo_empty_i,
    output logic        fifo_rd_en_o,
    output logic [127:0] m_axis_tdata_o,
    output logic [15:0] m_axis_tkeep_o,
    output logic        m_axis_tvalid_o,
    input  wire         m_axis_tready_i,
    output logic        m_axis_tlast_o,
    output logic        busy_o,
    output logic        done_pulse_o
);
    logic [31:0] remaining_q;
    logic [127:0] buffer_q, buffer_with_new;
    logic [3:0] sample_in_beat_q;
    logic read_pending_q;

    always_comb begin
        buffer_with_new = buffer_q;
        buffer_with_new[sample_in_beat_q*16 +: 16] = fifo_data_i;
    end

    function automatic [15:0] keep_for_last(input [3:0] sample_index);
        begin
            case (sample_index)
                0: keep_for_last=16'h0003; 1: keep_for_last=16'h000f;
                2: keep_for_last=16'h003f; 3: keep_for_last=16'h00ff;
                4: keep_for_last=16'h03ff; 5: keep_for_last=16'h0fff;
                6: keep_for_last=16'h3fff; default: keep_for_last=16'hffff;
            endcase
        end
    endfunction

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            remaining_q<=0; buffer_q<=0; sample_in_beat_q<=0; read_pending_q<=0;
            fifo_rd_en_o<=0; m_axis_tdata_o<=0; m_axis_tkeep_o<=0;
            m_axis_tvalid_o<=0; m_axis_tlast_o<=0; busy_o<=0; done_pulse_o<=0;
        end else begin
            fifo_rd_en_o<=0; done_pulse_o<=0;
            if (clear_i) begin
                remaining_q<=0; buffer_q<=0; sample_in_beat_q<=0; read_pending_q<=0;
                m_axis_tvalid_o<=0; m_axis_tlast_o<=0; busy_o<=0;
            end else if (start_i && !busy_o) begin
                remaining_q<=sample_count_i; buffer_q<=0; sample_in_beat_q<=0;
                read_pending_q<=0; m_axis_tvalid_o<=0; m_axis_tlast_o<=0;
                busy_o <= (sample_count_i != 0);
            end else begin
                if (m_axis_tvalid_o && m_axis_tready_i) begin
                    m_axis_tvalid_o<=0;
                    if (m_axis_tlast_o) begin busy_o<=0; done_pulse_o<=1; end
                    m_axis_tlast_o<=0;
                end
                if (busy_o && !m_axis_tvalid_o) begin
                    if (fifo_valid_i && read_pending_q) begin
                        read_pending_q<=0;
                        remaining_q<=remaining_q-1'b1;
                        if (sample_in_beat_q==7 || remaining_q==1) begin
                            m_axis_tdata_o<=buffer_with_new;
                            m_axis_tkeep_o<=keep_for_last(sample_in_beat_q);
                            m_axis_tvalid_o<=1'b1;
                            m_axis_tlast_o<=(remaining_q==1);
                            buffer_q<=0; sample_in_beat_q<=0;
                        end else begin
                            buffer_q<=buffer_with_new;
                            sample_in_beat_q<=sample_in_beat_q+1'b1;
                        end
                    end else if (!read_pending_q && remaining_q!=0 && !fifo_empty_i) begin
                        fifo_rd_en_o<=1'b1;
                        read_pending_q<=1'b1;
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
