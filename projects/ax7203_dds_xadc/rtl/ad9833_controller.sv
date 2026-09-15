`timescale 1ns/1ps
`default_nettype none

module ad9833_controller #(
    parameter integer CLK_DIV=16
) (
    input wire clk_i,input wire rst_ni,input wire apply_i,
    input wire [27:0] ftw_i,input wire triangle_i,
    output logic busy_o,output logic done_pulse_o,
    output logic sclk_o,output logic fsync_no,output logic sdata_o
);
    localparam integer DIV_W=(CLK_DIV<=1)?1:$clog2(CLK_DIV);
    localparam [2:0] IDLE=0,FALL=1,RISE=2,GAP=3,DONE=4;
    logic [2:0] state_q,word_q; logic [4:0] bit_q;
    logic [DIV_W-1:0] div_q; logic [27:0] ftw_q;
    logic triangle_q; logic [15:0] shift_q, next_word;

    function automatic [15:0] make_word;
        input [2:0] index;
        input [27:0] frequency_word;
        input triangle_wave;
        begin
            case(index)
                0: make_word=16'h2100;
                1: make_word={2'b01,frequency_word[13:0]};
                2: make_word={2'b01,frequency_word[27:14]};
                3: make_word=16'hc000;
                default: make_word=triangle_wave ? 16'h2002 : 16'h2000;
            endcase
        end
    endfunction

    always_comb next_word=make_word(word_q+1'b1,ftw_q,triangle_q);
    wire tick=(div_q==CLK_DIV-1);
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            state_q<=IDLE;word_q<=0;bit_q<=15;div_q<=0;ftw_q<=0;
            triangle_q<=0;shift_q<=0;busy_o<=0;done_pulse_o<=0;
            sclk_o<=1;fsync_no<=1;sdata_o<=0;
        end else begin
            done_pulse_o<=0;
            if(state_q==IDLE) begin
                div_q<=0;
                if(apply_i) begin
                    ftw_q<=ftw_i;triangle_q<=triangle_i;
                    shift_q<=make_word(0,ftw_i,triangle_i);
                    word_q<=0;bit_q<=15;busy_o<=1;
                    fsync_no<=0;sclk_o<=1;sdata_o<=0;state_q<=FALL;
                end
            end else if(tick) begin
                div_q<=0;
                case(state_q)
                    FALL: begin sclk_o<=0;state_q<=RISE;end
                    RISE: begin
                        sclk_o<=1;
                        if(bit_q==0) begin fsync_no<=1;state_q<=GAP;end
                        else begin
                            bit_q<=bit_q-1'b1;shift_q<={shift_q[14:0],1'b0};
                            sdata_o<=shift_q[14];state_q<=FALL;
                        end
                    end
                    GAP: begin
                        if(word_q==4) state_q<=DONE;
                        else begin
                            word_q<=word_q+1'b1;bit_q<=15;
                            shift_q<=next_word;
                            sdata_o<=next_word[15];fsync_no<=0;state_q<=FALL;
                        end
                    end
                    DONE: begin busy_o<=0;done_pulse_o<=1;state_q<=IDLE;end
                    default: state_q<=IDLE;
                endcase
            end else div_q<=div_q+1'b1;
        end
    end
`ifndef SYNTHESIS
    initial if(CLK_DIV<1) $error("CLK_DIV must be >= 1");
`endif
endmodule
`default_nettype wire
