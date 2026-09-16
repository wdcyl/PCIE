`timescale 1ns/1ps
`default_nettype none
module axi_burst_writer #(
    parameter integer ADDR_WIDTH=32,
    parameter integer MAX_BURST_BEATS=64
) (
    input wire clk_i, input wire rst_ni, input wire start_i,
    input wire clear_i, input wire abort_i,
    input wire [ADDR_WIDTH-1:0] base_addr_i,
    input wire [31:0] transfer_bytes_i,
    output wire ready_o, output logic done_pulse_o, output logic error_o,
    input wire [127:0] s_data_i, input wire s_valid_i, output wire s_ready_o,
    output wire [3:0] m_axi_awid_o,
    output wire [ADDR_WIDTH-1:0] m_axi_awaddr_o,
    output wire [7:0] m_axi_awlen_o, output wire [2:0] m_axi_awsize_o,
    output wire [1:0] m_axi_awburst_o, output wire m_axi_awlock_o,
    output wire [3:0] m_axi_awcache_o, output wire [2:0] m_axi_awprot_o,
    output wire [3:0] m_axi_awqos_o, output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [127:0] m_axi_wdata_o, output wire [15:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o, output wire m_axi_wvalid_o,
    input wire m_axi_wready_i, input wire [3:0] m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i, input wire m_axi_bvalid_i,
    output wire m_axi_bready_o
);
    localparam [2:0] ST_IDLE=0,ST_PREP=1,ST_AW=2,ST_W=3,ST_B=4;
    logic [2:0] state_q;
    logic [ADDR_WIDTH-1:0] addr_q;
    logic [31:0] remaining_q;
    logic [8:0] burst_beats_q,beat_index_q,next_burst,boundary_beats;
    always_comb begin
        boundary_beats=(12'h000-addr_q[11:0])>>4;
        if(addr_q[11:0]==0) boundary_beats=9'd256;
        next_burst=(remaining_q>MAX_BURST_BEATS)?MAX_BURST_BEATS:remaining_q[8:0];
        if(next_burst>boundary_beats) next_burst=boundary_beats;
    end
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            state_q<=ST_IDLE; addr_q<='0; remaining_q<=0; burst_beats_q<=0;
            beat_index_q<=0; done_pulse_o<=0; error_o<=0;
        end else begin
            done_pulse_o<=0;
            if(clear_i) error_o<=0;
            if(abort_i && state_q!=ST_IDLE) begin
                state_q<=ST_IDLE; error_o<=1; done_pulse_o<=1;
            end else case(state_q)
                ST_IDLE: if(start_i) begin
                    error_o<=0;
                    if((transfer_bytes_i<16)||(transfer_bytes_i[3:0]!=0)||(base_addr_i[3:0]!=0)) begin
                        error_o<=1; done_pulse_o<=1;
                    end else begin
                        addr_q<=base_addr_i; remaining_q<=transfer_bytes_i>>4; state_q<=ST_PREP;
                    end
                end
                ST_PREP: begin burst_beats_q<=next_burst; beat_index_q<=0; state_q<=ST_AW; end
                ST_AW: if(m_axi_awready_i) state_q<=ST_W;
                ST_W: if(s_valid_i&&m_axi_wready_i) begin
                    if(beat_index_q+1'b1==burst_beats_q) state_q<=ST_B;
                    else beat_index_q<=beat_index_q+1'b1;
                end
                ST_B: if(m_axi_bvalid_i) begin
                    if(m_axi_bresp_i!=2'b00) error_o<=1;
                    if(remaining_q==burst_beats_q) begin state_q<=ST_IDLE; done_pulse_o<=1; end
                    else begin
                        remaining_q<=remaining_q-burst_beats_q;
                        addr_q<=addr_q+(burst_beats_q<<4); state_q<=ST_PREP;
                    end
                end
                default: state_q<=ST_IDLE;
            endcase
        end
    end
    assign ready_o=(state_q==ST_IDLE);
    assign s_ready_o=(state_q==ST_W)&&m_axi_wready_i;
    assign m_axi_awid_o=0; assign m_axi_awaddr_o=addr_q;
    assign m_axi_awlen_o=burst_beats_q-1'b1; assign m_axi_awsize_o=3'b100;
    assign m_axi_awburst_o=2'b01; assign m_axi_awlock_o=0;
    assign m_axi_awcache_o=4'b0011; assign m_axi_awprot_o=0; assign m_axi_awqos_o=0;
    assign m_axi_awvalid_o=(state_q==ST_AW);
    assign m_axi_wdata_o=s_data_i; assign m_axi_wstrb_o=16'hffff;
    assign m_axi_wlast_o=(beat_index_q+1'b1==burst_beats_q);
    assign m_axi_wvalid_o=(state_q==ST_W)&&s_valid_i;
    assign m_axi_bready_o=(state_q==ST_B);
    wire _unused=&{1'b0,m_axi_bid_i};
endmodule
`default_nettype wire
