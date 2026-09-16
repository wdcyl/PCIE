`timescale 1ns/1ps
`default_nettype none
module axi_test_source (
    input wire clk_i,input wire rst_ni,input wire start_i,input wire clear_i,
    input wire [31:0] transfer_bytes_i,input wire [31:0] seed_i,
    output wire [127:0] data_o,output wire valid_o,input wire ready_i,output wire busy_o
);
    logic busy_q;logic [31:0] words_left_q,value_q;
    always_ff @(posedge clk_i or negedge rst_ni)begin
        if(!rst_ni)begin busy_q<=0;words_left_q<=0;value_q<=0;end
        else begin
            if(clear_i)busy_q<=0;
            if(start_i)begin
                busy_q<=(transfer_bytes_i>=16)&&(transfer_bytes_i[3:0]==0);
                words_left_q<=transfer_bytes_i>>4;value_q<=seed_i;
            end else if(busy_q&&ready_i)begin
                value_q<=value_q+32'd4;words_left_q<=words_left_q-1'b1;
                if(words_left_q==1)busy_q<=0;
            end
        end
    end
    assign data_o={value_q+32'd3,value_q+32'd2,value_q+32'd1,value_q};
    assign valid_o=busy_q;assign busy_o=busy_q;
endmodule
`default_nettype wire
