`timescale 1ns/1ps
`default_nettype none

// Single-vector MSI request controller for the 7-Series PCIe Integrated Block.
// IRQ status remains owned by the BAR register bank and is only cleared by the
// host driver through IRQ_CLEAR. cfg_interrupt_rdy acknowledges transmission of
// the MSI message; it does not acknowledge the underlying device event.
module xilinx_7x_msi_controller (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        link_up_i,
    input  logic        irq_pending_i,
    input  logic        cfg_interrupt_msienable_i,
    input  logic        cfg_interrupt_rdy_i,

    output logic        cfg_interrupt_o,
    output logic        cfg_interrupt_assert_o,
    output logic [7:0]  cfg_interrupt_di_o,
    output logic        cfg_interrupt_stat_o,
    output logic [4:0]  cfg_pciecap_interrupt_msgnum_o,
    output logic        request_active_o,
    output logic [31:0] msi_sent_count_o
);

    typedef enum logic [1:0] {
        MSI_IDLE,
        MSI_REQUEST,
        MSI_WAIT_CLEAR
    } msi_state_t;

    msi_state_t state_q;

    assign cfg_interrupt_assert_o = 1'b0;
    assign cfg_interrupt_di_o = 8'h00;
    assign cfg_interrupt_stat_o = 1'b0;
    assign cfg_pciecap_interrupt_msgnum_o = 5'd0;
    assign request_active_o = (state_q == MSI_REQUEST);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q          <= MSI_IDLE;
            cfg_interrupt_o  <= 1'b0;
            msi_sent_count_o <= 32'd0;
        end else begin
            case (state_q)
                MSI_IDLE: begin
                    cfg_interrupt_o <= 1'b0;
                    if (link_up_i && cfg_interrupt_msienable_i &&
                        irq_pending_i) begin
                        cfg_interrupt_o <= 1'b1;
                        state_q         <= MSI_REQUEST;
                    end
                end

                MSI_REQUEST: begin
                    // Never fall back to legacy INTx if the host disables MSI.
                    if (!link_up_i || !cfg_interrupt_msienable_i) begin
                        cfg_interrupt_o <= 1'b0;
                        state_q         <= MSI_IDLE;
                    end else if (cfg_interrupt_rdy_i) begin
                        cfg_interrupt_o  <= 1'b0;
                        msi_sent_count_o <= msi_sent_count_o + 1'b1;
                        state_q          <= MSI_WAIT_CLEAR;
                    end
                end

                MSI_WAIT_CLEAR: begin
                    cfg_interrupt_o <= 1'b0;
                    // One MSI is emitted for each non-zero pending episode.
                    // The ISR must process and W1C IRQ_CLEAR until pending=0.
                    if (!irq_pending_i)
                        state_q <= MSI_IDLE;
                end

                default: begin
                    state_q         <= MSI_IDLE;
                    cfg_interrupt_o <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
