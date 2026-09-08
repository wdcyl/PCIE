`timescale 1ns/1ps
`default_nettype none

// Two-input, one-beat TLP arbiter with an output holding register.
// Completion traffic has priority so host MMIO reads cannot be starved by DMA.
module tlp_tx_arbiter (
    input  logic         clk_i,
    input  logic         rst_ni,
    input  logic [255:0] cpl_data_i,
    input  logic [31:0]  cpl_keep_i,
    input  logic         cpl_valid_i,
    output logic         cpl_ready_o,
    input  logic [255:0] dma_data_i,
    input  logic [31:0]  dma_keep_i,
    input  logic         dma_valid_i,
    output logic         dma_ready_o,
    output logic [255:0] tx_data_o,
    output logic [31:0]  tx_keep_o,
    output logic         tx_valid_o,
    input  logic         tx_ready_i,
    output logic         tx_last_o
);

    logic [255:0] data_q;
    logic [31:0]  keep_q;
    logic         valid_q;
    logic         slot_available;

    assign slot_available = !valid_q || tx_ready_i;
    assign cpl_ready_o     = slot_available;
    assign dma_ready_o     = slot_available && !cpl_valid_i;
    assign tx_data_o       = data_q;
    assign tx_keep_o       = keep_q;
    assign tx_valid_o      = valid_q;
    assign tx_last_o       = 1'b1;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            data_q  <= '0;
            keep_q  <= '0;
            valid_q <= 1'b0;
        end else begin
            if (valid_q && tx_ready_i)
                valid_q <= 1'b0;
            if (cpl_valid_i && cpl_ready_o) begin
                data_q  <= cpl_data_i;
                keep_q  <= cpl_keep_i;
                valid_q <= 1'b1;
            end else if (dma_valid_i && dma_ready_o) begin
                data_q  <= dma_data_i;
                keep_q  <= dma_keep_i;
                valid_q <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
