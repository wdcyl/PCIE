`timescale 1ns/1ps

// Acquisition control and status CDC bridge.
//
// CDC contract for sample_count_cfg:
//   sample_count_cfg is a bundled-data bus.  Software/control logic must make
//   it stable for at least two adc_clk cycles before pulsing start, and hold it
//   stable until busy is observed in the pcie_clk domain.  The start and clear
//   commands use toggle synchronizers, so a new pulse must not be issued until
//   the previous command has had time to cross the clock boundary.  The two
//   resets are expected to be asserted together during system reset.
//
// captured_count counts samples successfully written into the FIFO.  Samples
// arriving while the FIFO is full are counted in dropped_count and set the
// sticky overflow flag; they do not advance captured_count.  Acquisition thus
// completes only after sample_count_cfg samples have actually entered the FIFO.
module acquisition_controller (
    input  wire         pcie_clk,
    input  wire         pcie_rst_n,
    input  wire         start,
    input  wire         clear_status,
    input  wire [31:0]  sample_count_cfg,

    output logic        busy,
    output logic        done,
    output logic        overflow,
    output logic [31:0] captured_count,
    output logic [31:0] dropped_count,

    input  wire         adc_clk,
    input  wire         adc_rst_n,
    input  wire [15:0]  adc_data,
    input  wire         adc_valid,
    input  wire         fifo_full,
    output logic        fifo_wr_en,
    output logic [15:0] fifo_wr_data
);

    logic start_toggle_pcie;
    logic clear_toggle_pcie;

    (* ASYNC_REG = "TRUE" *) logic start_sync1_adc;
    (* ASYNC_REG = "TRUE" *) logic start_sync2_adc;
    logic start_sync2_adc_d;
    (* ASYNC_REG = "TRUE" *) logic clear_sync1_adc;
    (* ASYNC_REG = "TRUE" *) logic clear_sync2_adc;
    logic clear_sync2_adc_d;

    (* ASYNC_REG = "TRUE" *) logic [31:0] sample_count_sync1_adc;
    (* ASYNC_REG = "TRUE" *) logic [31:0] sample_count_sync2_adc;

    wire start_event_adc = start_sync2_adc ^ start_sync2_adc_d;
    wire clear_event_adc = clear_sync2_adc ^ clear_sync2_adc_d;

    logic        busy_adc;
    logic        done_adc;
    logic        overflow_adc;
    logic [31:0] target_count_adc;
    logic [31:0] captured_count_adc;
    logic [31:0] dropped_count_adc;
    logic [31:0] captured_gray_adc;
    logic [31:0] dropped_gray_adc;

    (* ASYNC_REG = "TRUE" *) logic busy_sync1_pcie;
    (* ASYNC_REG = "TRUE" *) logic busy_sync2_pcie;
    (* ASYNC_REG = "TRUE" *) logic done_sync1_pcie;
    (* ASYNC_REG = "TRUE" *) logic done_sync2_pcie;
    (* ASYNC_REG = "TRUE" *) logic overflow_sync1_pcie;
    (* ASYNC_REG = "TRUE" *) logic overflow_sync2_pcie;
    (* ASYNC_REG = "TRUE" *) logic [31:0] captured_gray_sync1_pcie;
    (* ASYNC_REG = "TRUE" *) logic [31:0] captured_gray_sync2_pcie;
    (* ASYNC_REG = "TRUE" *) logic [31:0] dropped_gray_sync1_pcie;
    (* ASYNC_REG = "TRUE" *) logic [31:0] dropped_gray_sync2_pcie;

    function automatic [31:0] bin_to_gray32(input [31:0] value);
        begin
            bin_to_gray32 = (value >> 1) ^ value;
        end
    endfunction

    function automatic [31:0] gray_to_bin32(input [31:0] value);
        integer bit_index;
        begin
            gray_to_bin32[31] = value[31];
            for (bit_index = 30; bit_index >= 0; bit_index = bit_index - 1)
                gray_to_bin32[bit_index] = gray_to_bin32[bit_index+1] ^ value[bit_index];
        end
    endfunction

    // Convert command pulses to toggles; unlike a pulse, a toggle is not lost
    // merely because the destination clock is slower.
    always_ff @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            start_toggle_pcie <= 1'b0;
            clear_toggle_pcie <= 1'b0;
        end else begin
            if (start)
                start_toggle_pcie <= ~start_toggle_pcie;
            if (clear_status)
                clear_toggle_pcie <= ~clear_toggle_pcie;
        end
    end

    always_ff @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            start_sync1_adc         <= 1'b0;
            start_sync2_adc         <= 1'b0;
            start_sync2_adc_d       <= 1'b0;
            clear_sync1_adc         <= 1'b0;
            clear_sync2_adc         <= 1'b0;
            clear_sync2_adc_d       <= 1'b0;
            sample_count_sync1_adc  <= 32'd0;
            sample_count_sync2_adc  <= 32'd0;
        end else begin
            start_sync1_adc        <= start_toggle_pcie;
            start_sync2_adc        <= start_sync1_adc;
            start_sync2_adc_d      <= start_sync2_adc;
            clear_sync1_adc        <= clear_toggle_pcie;
            clear_sync2_adc        <= clear_sync1_adc;
            clear_sync2_adc_d      <= clear_sync2_adc;
            sample_count_sync1_adc <= sample_count_cfg;
            sample_count_sync2_adc <= sample_count_sync1_adc;
        end
    end

    always_ff @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            busy_adc           <= 1'b0;
            done_adc           <= 1'b0;
            overflow_adc       <= 1'b0;
            target_count_adc   <= 32'd0;
            captured_count_adc <= 32'd0;
            dropped_count_adc  <= 32'd0;
            captured_gray_adc  <= 32'd0;
            dropped_gray_adc   <= 32'd0;
            fifo_wr_en         <= 1'b0;
            fifo_wr_data       <= 16'd0;
        end else begin
            fifo_wr_en <= 1'b0;

            if (start_event_adc && !busy_adc) begin
                target_count_adc   <= sample_count_sync2_adc;
                captured_count_adc <= 32'd0;
                captured_gray_adc  <= 32'd0;
                overflow_adc       <= 1'b0;

                if (sample_count_sync2_adc == 32'd0) begin
                    busy_adc <= 1'b0;
                    done_adc <= 1'b1;
                end else begin
                    busy_adc <= 1'b1;
                    done_adc <= 1'b0;
                end
            end else if (clear_event_adc) begin
                done_adc          <= 1'b0;
                overflow_adc      <= 1'b0;
                dropped_count_adc <= 32'd0;
                dropped_gray_adc  <= 32'd0;

                if (!busy_adc) begin
                    captured_count_adc <= 32'd0;
                    captured_gray_adc  <= 32'd0;
                end
            end else if (busy_adc && adc_valid) begin
                if (!fifo_full) begin
                    fifo_wr_en         <= 1'b1;
                    fifo_wr_data       <= adc_data;
                    captured_count_adc <= captured_count_adc + 1'b1;
                    captured_gray_adc  <= bin_to_gray32(captured_count_adc + 1'b1);

                    if ((captured_count_adc + 1'b1) >= target_count_adc) begin
                        busy_adc <= 1'b0;
                        done_adc <= 1'b1;
                    end
                end else begin
                    overflow_adc <= 1'b1;
                    if (dropped_count_adc != 32'hFFFF_FFFF) begin
                        dropped_count_adc <= dropped_count_adc + 1'b1;
                        dropped_gray_adc  <= bin_to_gray32(dropped_count_adc + 1'b1);
                    end
                end
            end
        end
    end

    // Level status and Gray-coded counters cross back into pcie_clk.  Gray
    // counters remain coherent even while acquisition is active.
    always_ff @(posedge pcie_clk or negedge pcie_rst_n) begin
        if (!pcie_rst_n) begin
            busy_sync1_pcie          <= 1'b0;
            busy_sync2_pcie          <= 1'b0;
            done_sync1_pcie          <= 1'b0;
            done_sync2_pcie          <= 1'b0;
            overflow_sync1_pcie      <= 1'b0;
            overflow_sync2_pcie      <= 1'b0;
            captured_gray_sync1_pcie <= 32'd0;
            captured_gray_sync2_pcie <= 32'd0;
            dropped_gray_sync1_pcie  <= 32'd0;
            dropped_gray_sync2_pcie  <= 32'd0;
            busy                     <= 1'b0;
            done                     <= 1'b0;
            overflow                 <= 1'b0;
            captured_count           <= 32'd0;
            dropped_count            <= 32'd0;
        end else begin
            busy_sync1_pcie          <= busy_adc;
            busy_sync2_pcie          <= busy_sync1_pcie;
            done_sync1_pcie          <= done_adc;
            done_sync2_pcie          <= done_sync1_pcie;
            overflow_sync1_pcie      <= overflow_adc;
            overflow_sync2_pcie      <= overflow_sync1_pcie;
            captured_gray_sync1_pcie <= captured_gray_adc;
            captured_gray_sync2_pcie <= captured_gray_sync1_pcie;
            dropped_gray_sync1_pcie  <= dropped_gray_adc;
            dropped_gray_sync2_pcie  <= dropped_gray_sync1_pcie;

            busy           <= busy_sync2_pcie;
            done           <= done_sync2_pcie;
            overflow       <= overflow_sync2_pcie;
            captured_count <= gray_to_bin32(captured_gray_sync2_pcie);
            dropped_count  <= gray_to_bin32(dropped_gray_sync2_pcie);
        end
    end

endmodule
