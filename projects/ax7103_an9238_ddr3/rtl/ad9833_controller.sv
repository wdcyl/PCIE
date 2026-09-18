`timescale 1ns/1ps
`default_nettype none

module ad9833_controller #(
    parameter integer CLK_DIV = 16
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        apply_i,
    input  wire [27:0] ftw_i,
    input  wire        triangle_i,
    output logic       busy_o,
    output logic       done_pulse_o,
    output logic       sclk_o,
    output logic       fsync_no,
    output logic       sdata_o
);
    localparam integer DIV_W = (CLK_DIV <= 2) ? 1 : $clog2(CLK_DIV);
    logic [DIV_W-1:0] div_q;
    logic [2:0] word_index_q;
    logic [4:0] bit_index_q;
    logic [15:0] shift_q;
    logic [27:0] ftw_q;
    logic triangle_q;
    logic gap_q;

    function automatic [15:0] command_word(input [2:0] index,input [27:0] ftw,input logic triangle);
        begin
            case(index)
                3'd0: command_word=16'h2100;
                3'd1: command_word={2'b01,ftw[13:0]};
                3'd2: command_word={2'b01,ftw[27:14]};
                3'd3: command_word=16'hc000;
                default: command_word=triangle?16'h2002:16'h2000;
            endcase
        end
    endfunction

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            div_q<=0;word_index_q<=0;bit_index_q<=0;shift_q<=0;ftw_q<=0;triangle_q<=0;
            busy_o<=0;done_pulse_o<=0;sclk_o<=1;fsync_no<=1;sdata_o<=0;gap_q<=0;
        end else begin
            done_pulse_o<=0;
            if(apply_i&&!busy_o) begin
                ftw_q<=ftw_i;triangle_q<=triangle_i;word_index_q<=0;bit_index_q<=0;
                shift_q<=command_word(0,ftw_i,triangle_i);sdata_o<=1'b0;
                div_q<=0;busy_o<=1;fsync_no<=0;sclk_o<=1;gap_q<=0;
            end else if(busy_o) begin
                if(div_q==CLK_DIV-1) begin
                    div_q<=0;
                    if(gap_q) begin
                        gap_q<=0;fsync_no<=0;sclk_o<=1;bit_index_q<=0;
                        shift_q<=command_word(word_index_q,ftw_q,triangle_q);
                        sdata_o<=(word_index_q==3);
                    end else if(sclk_o) begin
                        sclk_o<=0;
                    end else begin
                        sclk_o<=1;
                        if(bit_index_q==15) begin
                            fsync_no<=1;
                            if(word_index_q==4) begin
                                busy_o<=0;done_pulse_o<=1;
                            end else begin
                                word_index_q<=word_index_q+1'b1;gap_q<=1;
                            end
                        end else begin
                            bit_index_q<=bit_index_q+1'b1;
                            shift_q<={shift_q[14:0],1'b0};sdata_o<=shift_q[14];
                        end
                    end
                end else div_q<=div_q+1'b1;
            end
        end
    end
endmodule

`default_nettype wire
