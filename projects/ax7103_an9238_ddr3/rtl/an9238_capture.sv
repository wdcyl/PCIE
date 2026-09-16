`timescale 1ns/1ps
`default_nettype none

// Captures simultaneous AN9238 channel samples and packs four sample pairs
// into one 128-bit word. Control/status cross between the AXI and ADC clocks.
module an9238_capture (
    input  wire         ctrl_clk_i,
    input  wire         ctrl_rst_ni,
    input  wire         start_i,
    input  wire         clear_i,
    input  wire [31:0]  sample_pairs_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         overflow_o,
    output wire [31:0]  captured_pairs_o,

    input  wire         adc_clk_i,
    input  wire         adc_rst_ni,
    input  wire [11:0]  adc_ch0_i,
    input  wire [11:0]  adc_ch1_i,
    output logic        fifo_wr_en_o,
    output logic [127:0] fifo_wr_data_o,
    input  wire         fifo_full_i
);
    logic start_toggle_q, clear_toggle_q;
    logic start_s1_q, start_s2_q, start_seen_q;
    logic clear_s1_q, clear_s2_q, clear_seen_q;
    logic [31:0] count_s1_q, count_s2_q;
    logic busy_adc_q, done_adc_q, overflow_adc_q;
    logic [31:0] captured_adc_q;
    logic [1:0] pack_index_q;
    logic [127:0] pack_q;

    logic busy_s1_q, busy_s2_q, done_s1_q, done_s2_q;
    logic overflow_s1_q, overflow_s2_q;
    logic [31:0] captured_s1_q, captured_s2_q;

    wire start_event = start_s2_q ^ start_seen_q;
    wire clear_event = clear_s2_q ^ clear_seen_q;
    wire [31:0] sample_pair = {4'b0, adc_ch1_i, 4'b0, adc_ch0_i};

    always_ff @(posedge ctrl_clk_i or negedge ctrl_rst_ni) begin
        if (!ctrl_rst_ni) begin
            start_toggle_q <= 1'b0;
            clear_toggle_q <= 1'b0;
        end else begin
            if (start_i) start_toggle_q <= ~start_toggle_q;
            if (clear_i) clear_toggle_q <= ~clear_toggle_q;
        end
    end

    always_ff @(posedge adc_clk_i or negedge adc_rst_ni) begin
        if (!adc_rst_ni) begin
            start_s1_q <= 1'b0; start_s2_q <= 1'b0; start_seen_q <= 1'b0;
            clear_s1_q <= 1'b0; clear_s2_q <= 1'b0; clear_seen_q <= 1'b0;
            count_s1_q <= 32'd0; count_s2_q <= 32'd0;
            busy_adc_q <= 1'b0; done_adc_q <= 1'b0; overflow_adc_q <= 1'b0;
            captured_adc_q <= 32'd0; pack_index_q <= 2'd0; pack_q <= 128'd0;
            fifo_wr_en_o <= 1'b0; fifo_wr_data_o <= 128'd0;
        end else begin
            start_s1_q <= start_toggle_q;
            start_s2_q <= start_s1_q;
            clear_s1_q <= clear_toggle_q;
            clear_s2_q <= clear_s1_q;
            count_s1_q <= sample_pairs_i;
            count_s2_q <= count_s1_q;
            fifo_wr_en_o <= 1'b0;

            if (clear_event) begin
                clear_seen_q <= clear_s2_q;
                busy_adc_q <= 1'b0;
                done_adc_q <= 1'b0;
                overflow_adc_q <= 1'b0;
                captured_adc_q <= 32'd0;
                pack_index_q <= 2'd0;
            end else if (start_event) begin
                start_seen_q <= start_s2_q;
                done_adc_q <= 1'b0;
                overflow_adc_q <= 1'b0;
                captured_adc_q <= 32'd0;
                pack_index_q <= 2'd0;
                busy_adc_q <= (count_s2_q != 0) && (count_s2_q[1:0] == 2'b00);
                if ((count_s2_q == 0) || (count_s2_q[1:0] != 2'b00)) begin
                    done_adc_q <= 1'b1;
                    overflow_adc_q <= 1'b1;
                end
            end else if (busy_adc_q) begin
                if ((pack_index_q == 2'd3) && fifo_full_i) begin
                    // ADC cannot be back-pressured. Abort rather than silently
                    // presenting a discontinuous record as a valid acquisition.
                    busy_adc_q <= 1'b0;
                    done_adc_q <= 1'b1;
                    overflow_adc_q <= 1'b1;
                end else begin
                    pack_q[pack_index_q*32 +: 32] <= sample_pair;
                    captured_adc_q <= captured_adc_q + 1'b1;
                    if (pack_index_q == 2'd3) begin
                        fifo_wr_data_o <= {sample_pair, pack_q[95:0]};
                        fifo_wr_en_o <= 1'b1;
                        pack_index_q <= 2'd0;
                    end else begin
                        pack_index_q <= pack_index_q + 1'b1;
                    end
                    if (captured_adc_q + 1'b1 == count_s2_q) begin
                        busy_adc_q <= 1'b0;
                        done_adc_q <= 1'b1;
                    end
                end
            end
        end
    end

    always_ff @(posedge ctrl_clk_i or negedge ctrl_rst_ni) begin
        if (!ctrl_rst_ni) begin
            busy_s1_q <= 1'b0; busy_s2_q <= 1'b0;
            done_s1_q <= 1'b0; done_s2_q <= 1'b0;
            overflow_s1_q <= 1'b0; overflow_s2_q <= 1'b0;
            captured_s1_q <= 32'd0; captured_s2_q <= 32'd0;
        end else begin
            busy_s1_q <= busy_adc_q; busy_s2_q <= busy_s1_q;
            done_s1_q <= done_adc_q; done_s2_q <= done_s1_q;
            overflow_s1_q <= overflow_adc_q; overflow_s2_q <= overflow_s1_q;
            captured_s1_q <= captured_adc_q; captured_s2_q <= captured_s1_q;
        end
    end

    assign busy_o = busy_s2_q;
    assign done_o = done_s2_q;
    assign overflow_o = overflow_s2_q;
    assign captured_pairs_o = captured_s2_q;
endmodule
`default_nettype wire
