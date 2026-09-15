`timescale 1ns/1ps
`default_nettype none

// Fixed-length single-channel capture with command/status clock crossing.
// Samples are stored as zero-extended 16-bit words: {4'b0, XADC[11:0]}.
module xadc_acquisition_controller (
    input  wire        user_clk_i,
    input  wire        user_rst_ni,
    input  wire        start_i,
    input  wire        clear_i,
    input  wire [31:0] sample_count_i,
    output logic       busy_o,
    output logic       done_o,
    output logic       overflow_o,
    output logic [31:0] captured_count_o,
    output logic [31:0] dropped_count_o,

    input  wire        sample_clk_i,
    input  wire        sample_rst_ni,
    input  wire [11:0] sample_i,
    input  wire        sample_valid_i,
    input  wire        fifo_full_i,
    output logic       fifo_wr_en_o,
    output logic [15:0] fifo_wr_data_o
);
    logic start_toggle_q, clear_toggle_q;
    (* ASYNC_REG = "TRUE" *) logic start_s1, start_s2, clear_s1, clear_s2;
    logic start_s2_d, clear_s2_d;
    (* ASYNC_REG = "TRUE" *) logic [31:0] count_s1, count_s2;
    logic sample_busy_q, sample_done_q, sample_overflow_q;
    logic [31:0] target_q, captured_q, dropped_q;
    logic [31:0] captured_gray_q, dropped_gray_q;
    (* ASYNC_REG = "TRUE" *) logic busy_s1, busy_s2, done_s1, done_s2;
    (* ASYNC_REG = "TRUE" *) logic overflow_s1, overflow_s2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] captured_s1, captured_s2;
    (* ASYNC_REG = "TRUE" *) logic [31:0] dropped_s1, dropped_s2;

    function automatic [31:0] bin_to_gray(input [31:0] v);
        bin_to_gray = v ^ (v >> 1);
    endfunction
    function automatic [31:0] gray_to_bin(input [31:0] v);
        integer i;
        begin
            gray_to_bin[31] = v[31];
            for (i=30; i>=0; i=i-1) gray_to_bin[i] = gray_to_bin[i+1] ^ v[i];
        end
    endfunction

    always_ff @(posedge user_clk_i or negedge user_rst_ni) begin
        if (!user_rst_ni) begin start_toggle_q <= 0; clear_toggle_q <= 0; end
        else begin
            if (start_i) start_toggle_q <= ~start_toggle_q;
            if (clear_i) clear_toggle_q <= ~clear_toggle_q;
        end
    end

    always_ff @(posedge sample_clk_i or negedge sample_rst_ni) begin
        if (!sample_rst_ni) begin
            start_s1<=0; start_s2<=0; start_s2_d<=0;
            clear_s1<=0; clear_s2<=0; clear_s2_d<=0; count_s1<=0; count_s2<=0;
        end else begin
            start_s1<=start_toggle_q; start_s2<=start_s1; start_s2_d<=start_s2;
            clear_s1<=clear_toggle_q; clear_s2<=clear_s1; clear_s2_d<=clear_s2;
            count_s1<=sample_count_i; count_s2<=count_s1;
        end
    end

    wire start_event = start_s2 ^ start_s2_d;
    wire clear_event = clear_s2 ^ clear_s2_d;

    always_ff @(posedge sample_clk_i or negedge sample_rst_ni) begin
        if (!sample_rst_ni) begin
            sample_busy_q<=0; sample_done_q<=0; sample_overflow_q<=0;
            target_q<=0; captured_q<=0; dropped_q<=0;
            captured_gray_q<=0; dropped_gray_q<=0;
            fifo_wr_en_o<=0; fifo_wr_data_o<=0;
        end else begin
            fifo_wr_en_o <= 1'b0;
            if (clear_event && !sample_busy_q) begin
                sample_done_q<=0; sample_overflow_q<=0;
                captured_q<=0; dropped_q<=0; captured_gray_q<=0; dropped_gray_q<=0;
            end
            if (start_event && !sample_busy_q) begin
                target_q<=count_s2; captured_q<=0; captured_gray_q<=0;
                dropped_q<=0; dropped_gray_q<=0; sample_overflow_q<=0;
                sample_busy_q <= (count_s2 != 0);
                sample_done_q <= (count_s2 == 0);
            end else if (sample_busy_q && sample_valid_i) begin
                if (!fifo_full_i) begin
                    fifo_wr_en_o <= 1'b1;
                    fifo_wr_data_o <= {4'd0, sample_i};
                    captured_q <= captured_q + 1'b1;
                    captured_gray_q <= bin_to_gray(captured_q + 1'b1);
                    if (captured_q + 1'b1 >= target_q) begin
                        sample_busy_q <= 1'b0;
                        sample_done_q <= 1'b1;
                    end
                end else begin
                    sample_overflow_q <= 1'b1;
                    if (dropped_q != 32'hffff_ffff) begin
                        dropped_q <= dropped_q + 1'b1;
                        dropped_gray_q <= bin_to_gray(dropped_q + 1'b1);
                    end
                end
            end
        end
    end

    always_ff @(posedge user_clk_i or negedge user_rst_ni) begin
        if (!user_rst_ni) begin
            busy_s1<=0; busy_s2<=0; done_s1<=0; done_s2<=0;
            overflow_s1<=0; overflow_s2<=0; captured_s1<=0; captured_s2<=0;
            dropped_s1<=0; dropped_s2<=0; busy_o<=0; done_o<=0;
            overflow_o<=0; captured_count_o<=0; dropped_count_o<=0;
        end else begin
            busy_s1<=sample_busy_q; busy_s2<=busy_s1;
            done_s1<=sample_done_q; done_s2<=done_s1;
            overflow_s1<=sample_overflow_q; overflow_s2<=overflow_s1;
            captured_s1<=captured_gray_q; captured_s2<=captured_s1;
            dropped_s1<=dropped_gray_q; dropped_s2<=dropped_s1;
            busy_o<=busy_s2; done_o<=done_s2; overflow_o<=overflow_s2;
            captured_count_o<=gray_to_bin(captured_s2);
            dropped_count_o<=gray_to_bin(dropped_s2);
        end
    end
endmodule

`default_nettype wire
