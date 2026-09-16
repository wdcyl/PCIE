`timescale 1ns/1ps
`default_nettype none
module fifo_stream_adapter #(parameter integer WIDTH=128) (
    input wire clk_i, input wire rst_ni, input wire clear_i,
    input wire [WIDTH-1:0] fifo_data_i, input wire fifo_valid_i,
    input wire fifo_empty_i, output logic fifo_rd_en_o,
    output wire [WIDTH-1:0] data_o, output wire valid_o, input wire ready_i
);
    logic [WIDTH-1:0] hold_q;
    logic hold_valid_q, read_pending_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            hold_q<='0; hold_valid_q<=0; read_pending_q<=0; fifo_rd_en_o<=0;
        end else if (clear_i) begin
            hold_q<='0; hold_valid_q<=0; read_pending_q<=0; fifo_rd_en_o<=0;
        end else begin
            fifo_rd_en_o<=0;
            if (!hold_valid_q && !read_pending_q && !fifo_empty_i) begin
                fifo_rd_en_o<=1; read_pending_q<=1;
            end
            if (fifo_valid_i) begin
                hold_q<=fifo_data_i; hold_valid_q<=1; read_pending_q<=0;
            end
            if (hold_valid_q && ready_i) hold_valid_q<=0;
        end
    end
    assign data_o=hold_q;
    assign valid_o=hold_valid_q;
endmodule
`default_nettype wire
