`timescale 1ns/1ps
`default_nettype none

// Full-rate 128-bit AXI4-Stream source for XDMA C2H throughput testing.
module axis_stress_source (
    input  wire          clk_i,
    input  wire          rst_ni,
    input  wire          start_i,
    input  wire          clear_i,
    input  wire [31:0]   transfer_bytes_i,
    input  wire [1:0]    pattern_i,
    input  wire [31:0]   seed_i,
    output logic [127:0] m_axis_tdata_o,
    output logic [15:0]  m_axis_tkeep_o,
    output logic         m_axis_tvalid_o,
    input  wire          m_axis_tready_i,
    output logic         m_axis_tlast_o,
    output logic         busy_o,
    output logic         done_pulse_o
);
    localparam [1:0] PATTERN_RAMP = 2'd0, PATTERN_PRBS = 2'd1;
    localparam [1:0] PATTERN_CONSTANT = 2'd2, PATTERN_TOGGLE = 2'd3;
    logic [31:0] remaining_q, state_q;
    logic [1:0] pattern_q;
    logic [31:0] lane0, lane1, lane2, lane3;

    function automatic [31:0] prbs_next(input [31:0] value);
        prbs_next = {value[30:0], value[31] ^ value[21] ^ value[1] ^ value[0]};
    endfunction

    always_comb begin
        case (pattern_q)
            PATTERN_PRBS: begin
                lane0 = state_q; lane1 = prbs_next(lane0);
                lane2 = prbs_next(lane1); lane3 = prbs_next(lane2);
            end
            PATTERN_CONSTANT: begin
                lane0 = state_q; lane1 = state_q; lane2 = state_q; lane3 = state_q;
            end
            PATTERN_TOGGLE: begin
                lane0 = state_q; lane1 = ~state_q; lane2 = state_q; lane3 = ~state_q;
            end
            default: begin
                lane0 = state_q; lane1 = state_q + 1; lane2 = state_q + 2; lane3 = state_q + 3;
            end
        endcase
        m_axis_tdata_o  = {lane3, lane2, lane1, lane0};
        m_axis_tvalid_o = busy_o;
        m_axis_tlast_o  = busy_o && (remaining_q <= 16);
        if (remaining_q >= 16) m_axis_tkeep_o = 16'hffff;
        else case (remaining_q[3:2])
            2'd1: m_axis_tkeep_o = 16'h000f;
            2'd2: m_axis_tkeep_o = 16'h00ff;
            2'd3: m_axis_tkeep_o = 16'h0fff;
            default: m_axis_tkeep_o = 16'hffff;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            remaining_q <= 0; state_q <= 0; pattern_q <= 0;
            busy_o <= 0; done_pulse_o <= 0;
        end else begin
            done_pulse_o <= 0;
            if (clear_i) begin
                remaining_q <= 0; busy_o <= 0;
            end else if (start_i && !busy_o) begin
                remaining_q <= transfer_bytes_i;
                state_q <= (seed_i == 0 && pattern_i == PATTERN_PRBS) ? 32'h1ace_beef : seed_i;
                pattern_q <= pattern_i;
                busy_o <= (transfer_bytes_i != 0);
            end else if (busy_o && m_axis_tready_i) begin
                if (remaining_q <= 16) begin
                    remaining_q <= 0; busy_o <= 0; done_pulse_o <= 1;
                end else remaining_q <= remaining_q - 16;
                case (pattern_q)
                    PATTERN_PRBS: begin
                        case (remaining_q[3:2])
                            1: state_q <= prbs_next(lane0);
                            2: state_q <= prbs_next(lane1);
                            3: state_q <= prbs_next(lane2);
                            default: state_q <= prbs_next(lane3);
                        endcase
                    end
                    PATTERN_CONSTANT: state_q <= state_q;
                    PATTERN_TOGGLE: state_q <= ~state_q;
                    default: state_q <= state_q + ((remaining_q < 16) ? {28'd0,remaining_q[3:2]} : 4);
                endcase
            end
        end
    end
endmodule

`default_nettype wire
