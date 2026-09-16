`timescale 1ns/1ps
`default_nettype none
module axil_acquisition_regs #(parameter integer ADDR_WIDTH=32) (
    input wire clk_i,input wire rst_ni,
    input wire [ADDR_WIDTH-1:0] s_axil_awaddr_i,input wire s_axil_awvalid_i,output logic s_axil_awready_o,
    input wire [31:0] s_axil_wdata_i,input wire [3:0] s_axil_wstrb_i,input wire s_axil_wvalid_i,output logic s_axil_wready_o,
    output logic [1:0] s_axil_bresp_o,output logic s_axil_bvalid_o,input wire s_axil_bready_i,
    input wire [ADDR_WIDTH-1:0] s_axil_araddr_i,input wire s_axil_arvalid_i,output logic s_axil_arready_o,
    output logic [31:0] s_axil_rdata_o,output logic [1:0] s_axil_rresp_o,output logic s_axil_rvalid_o,input wire s_axil_rready_i,
    input wire [31:0] status_i,input wire [31:0] captured_pairs_i,input wire [63:0] bytes_written_i,
    output logic start_pulse_o,output logic clear_pulse_o,output logic [31:0] capture_bytes_o,
    output logic [31:0] buffer_base_o,output logic [31:0] mode_o,output logic [31:0] test_seed_o
);
    localparam [11:0] REG_ID=12'h000,REG_VERSION=12'h004,REG_CONTROL=12'h008,REG_STATUS=12'h00c;
    localparam [11:0] REG_CAPTURE_BYTES=12'h010,REG_BUFFER_BASE=12'h014,REG_MODE=12'h018,REG_TEST_SEED=12'h01c;
    localparam [11:0] REG_CAPTURED=12'h020,REG_WRITTEN_LO=12'h024,REG_WRITTEN_HI=12'h028;
    logic aw_pending_q,w_pending_q; logic [11:0] awaddr_q; logic [31:0] wdata_q; logic [3:0] wstrb_q;
    wire aw_fire=s_axil_awvalid_i&&s_axil_awready_o, w_fire=s_axil_wvalid_i&&s_axil_wready_o;
    wire write_commit=!s_axil_bvalid_o&&(aw_pending_q||aw_fire)&&(w_pending_q||w_fire);
    wire [11:0] write_addr=aw_pending_q?awaddr_q:s_axil_awaddr_i[11:0];
    wire [31:0] write_data=w_pending_q?wdata_q:s_axil_wdata_i;
    wire [3:0] write_strb=w_pending_q?wstrb_q:s_axil_wstrb_i;
    function automatic [31:0] merge_wstrb(input [31:0] old_v,input [31:0] new_v,input [3:0] strb);
        integer k; begin merge_wstrb=old_v; for(k=0;k<4;k=k+1) if(strb[k]) merge_wstrb[k*8+:8]=new_v[k*8+:8]; end
    endfunction
    function automatic mapped(input [11:0] a); begin case(a)
        REG_ID,REG_VERSION,REG_CONTROL,REG_STATUS,REG_CAPTURE_BYTES,REG_BUFFER_BASE,REG_MODE,REG_TEST_SEED,
        REG_CAPTURED,REG_WRITTEN_LO,REG_WRITTEN_HI:mapped=1; default:mapped=0; endcase end endfunction
    function automatic [31:0] read_value(input [11:0] a); begin case(a)
        REG_ID:read_value=32'h4144_3932; REG_VERSION:read_value=32'h0002_0000; REG_STATUS:read_value=status_i;
        REG_CAPTURE_BYTES:read_value=capture_bytes_o; REG_BUFFER_BASE:read_value=buffer_base_o;
        REG_MODE:read_value=mode_o; REG_TEST_SEED:read_value=test_seed_o; REG_CAPTURED:read_value=captured_pairs_i;
        REG_WRITTEN_LO:read_value=bytes_written_i[31:0]; REG_WRITTEN_HI:read_value=bytes_written_i[63:32];
        default:read_value=0; endcase end endfunction
    always_comb begin s_axil_awready_o=!aw_pending_q&&!s_axil_bvalid_o; s_axil_wready_o=!w_pending_q&&!s_axil_bvalid_o; s_axil_arready_o=!s_axil_rvalid_o; end
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            aw_pending_q<=0;w_pending_q<=0;awaddr_q<=0;wdata_q<=0;wstrb_q<=0;s_axil_bresp_o<=0;s_axil_bvalid_o<=0;
            s_axil_rdata_o<=0;s_axil_rresp_o<=0;s_axil_rvalid_o<=0;start_pulse_o<=0;clear_pulse_o<=0;
            capture_bytes_o<=32'h0010_0000;buffer_base_o<=0;mode_o<=0;test_seed_o<=0;
        end else begin
            start_pulse_o<=0;clear_pulse_o<=0;
            if(aw_fire)begin aw_pending_q<=1;awaddr_q<=s_axil_awaddr_i[11:0];end
            if(w_fire)begin w_pending_q<=1;wdata_q<=s_axil_wdata_i;wstrb_q<=s_axil_wstrb_i;end
            if(write_commit)begin
                aw_pending_q<=0;w_pending_q<=0;s_axil_bvalid_o<=1;s_axil_bresp_o<=mapped(write_addr)?0:2'b10;
                case(write_addr)
                    REG_CONTROL:if(write_strb[0])begin start_pulse_o<=write_data[0];clear_pulse_o<=write_data[1];end
                    REG_CAPTURE_BYTES:capture_bytes_o<=merge_wstrb(capture_bytes_o,write_data,write_strb);
                    REG_BUFFER_BASE:buffer_base_o<=merge_wstrb(buffer_base_o,write_data,write_strb);
                    REG_MODE:mode_o<=merge_wstrb(mode_o,write_data,write_strb);
                    REG_TEST_SEED:test_seed_o<=merge_wstrb(test_seed_o,write_data,write_strb);
                    default:begin end
                endcase
            end else if(s_axil_bvalid_o&&s_axil_bready_i)s_axil_bvalid_o<=0;
            if(s_axil_arvalid_i&&s_axil_arready_o)begin
                s_axil_rdata_o<=read_value(s_axil_araddr_i[11:0]);s_axil_rresp_o<=mapped(s_axil_araddr_i[11:0])?0:2'b10;s_axil_rvalid_o<=1;
            end else if(s_axil_rvalid_o&&s_axil_rready_i)s_axil_rvalid_o<=0;
        end
    end
endmodule
`default_nettype wire
