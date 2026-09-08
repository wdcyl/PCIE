`timescale 1ns/1ps

// Synthesizable 16-bit ADC replacement used to exercise the acquisition path.
// A sample is emitted every VALID_DIV adc_clk cycles while enable is asserted.
module adc_pattern_source #(
    parameter integer VALID_DIV = 1,
    parameter [15:0]  PRBS_SEED = 16'h1ACE
) (
    input  wire         adc_clk,
    input  wire         adc_rst_n,
    input  wire         enable,
    input  wire         restart,
    input  wire [1:0]   pattern_sel,
    input  wire [15:0]  constant_value,
    output logic [15:0] sample_data,
    output logic        sample_valid
);

    localparam integer DIV_WIDTH = (VALID_DIV <= 1) ? 1 : $clog2(VALID_DIV);

    localparam [1:0] PATTERN_RAMP     = 2'd0;
    localparam [1:0] PATTERN_PRBS16   = 2'd1;
    localparam [1:0] PATTERN_CONSTANT = 2'd2;
    localparam [1:0] PATTERN_TRIANGLE = 2'd3;

    logic [DIV_WIDTH-1:0] div_count;
    logic [15:0] ramp_value;
    logic [15:0] lfsr;
    logic [15:0] triangle_value;
    logic        triangle_down;
    logic        emit_sample;
    logic        lfsr_feedback;

    always_comb begin
        if (VALID_DIV <= 1)
            emit_sample = enable;
        else
            emit_sample = enable && (div_count == VALID_DIV - 1);

        // x^16 + x^14 + x^13 + x^11 + 1 (maximal-length PRBS-16).
        lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];
    end

    always_ff @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            div_count      <= '0;
            ramp_value     <= 16'h0000;
            lfsr           <= (PRBS_SEED == 16'h0000) ? 16'h0001 : PRBS_SEED;
            triangle_value <= 16'h0000;
            triangle_down  <= 1'b0;
            sample_data    <= 16'h0000;
            sample_valid   <= 1'b0;
        end else begin
            sample_valid <= 1'b0;

            if (restart) begin
                div_count      <= '0;
                ramp_value     <= 16'h0000;
                lfsr           <= (PRBS_SEED == 16'h0000) ? 16'h0001 : PRBS_SEED;
                triangle_value <= 16'h0000;
                triangle_down  <= 1'b0;
            end else if (!enable) begin
                div_count <= '0;
            end else begin
                if (VALID_DIV > 1) begin
                    if (emit_sample)
                        div_count <= '0;
                    else
                        div_count <= div_count + 1'b1;
                end

                if (emit_sample) begin
                    sample_valid <= 1'b1;

                    case (pattern_sel)
                        PATTERN_RAMP: begin
                            sample_data <= ramp_value;
                            ramp_value  <= ramp_value + 1'b1;
                        end

                        PATTERN_PRBS16: begin
                            sample_data <= lfsr;
                            lfsr        <= {lfsr[14:0], lfsr_feedback};
                        end

                        PATTERN_CONSTANT: begin
                            sample_data <= constant_value;
                        end

                        default: begin
                            sample_data <= triangle_value;
                            if (!triangle_down) begin
                                if (triangle_value == 16'hFFFF) begin
                                    triangle_down  <= 1'b1;
                                    triangle_value <= 16'hFFFE;
                                end else begin
                                    triangle_value <= triangle_value + 1'b1;
                                end
                            end else begin
                                if (triangle_value == 16'h0000) begin
                                    triangle_down  <= 1'b0;
                                    triangle_value <= 16'h0001;
                                end else begin
                                    triangle_value <= triangle_value - 1'b1;
                                end
                            end
                        end
                    endcase
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (VALID_DIV < 1)
            $error("adc_pattern_source VALID_DIV must be >= 1");
    end
`endif

endmodule
