`timescale 1ns/1ps
`default_nettype none

// Register bank reached through XDMA's PCIe-to-AXI-Lite master BAR.
module axil_control_regs #(
    parameter integer ADDR_WIDTH = 32
) (
    input wire clk_i, input wire rst_ni,
    input wire [ADDR_WIDTH-1:0] s_axil_awaddr_i,
    input wire s_axil_awvalid_i, output logic s_axil_awready_o,
    input wire [31:0] s_axil_wdata_i, input wire [3:0] s_axil_wstrb_i,
    input wire s_axil_wvalid_i, output logic s_axil_wready_o,
    output logic [1:0] s_axil_bresp_o, output logic s_axil_bvalid_o,
    input wire s_axil_bready_i,
    input wire [ADDR_WIDTH-1:0] s_axil_araddr_i,
    input wire s_axil_arvalid_i, output logic s_axil_arready_o,
    output logic [31:0] s_axil_rdata_o, output logic [1:0] s_axil_rresp_o,
    output logic s_axil_rvalid_o, input wire s_axil_rready_i,

    input wire [31:0] status_i,
    input wire [63:0] stream_bytes_i,
    input wire [31:0] captured_samples_i,
    input wire [31:0] dropped_samples_i,
    input wire [31:0] backpressure_cycles_i,
    output logic start_pulse_o, output logic clear_pulse_o,
    output logic dds_apply_pulse_o,
    output logic [31:0] transfer_bytes_o,
    output logic [31:0] mode_o,
    output logic [31:0] stress_seed_o,
    output logic [27:0] dds_ftw_o,
    output logic dds_triangle_o
);
    localparam [11:0] REG_ID=12'h000, REG_VERSION=12'h004;
    localparam [11:0] REG_CONTROL=12'h008, REG_STATUS=12'h00c;
    localparam [11:0] REG_TRANSFER_BYTES=12'h010, REG_MODE=12'h014;
    localparam [11:0] REG_STRESS_SEED=12'h018, REG_DDS_FTW=12'h01c;
    localparam [11:0] REG_DDS_CONTROL=12'h020;
    localparam [11:0] REG_STREAM_LO=12'h028, REG_STREAM_HI=12'h02c;
    localparam [11:0] REG_CAPTURED=12'h030, REG_DROPPED=12'h034;
    localparam [11:0] REG_BACKPRESSURE=12'h038;

    logic aw_pending_q, w_pending_q;
    logic [11:0] awaddr_q;
    logic [31:0] wdata_q;
    logic [3:0] wstrb_q;
    wire aw_fire = s_axil_awvalid_i && s_axil_awready_o;
    wire w_fire  = s_axil_wvalid_i && s_axil_wready_o;
    wire write_commit = !s_axil_bvalid_o &&
        (aw_pending_q || aw_fire) && (w_pending_q || w_fire);
    wire [11:0] write_addr = aw_pending_q ? awaddr_q : s_axil_awaddr_i[11:0];
    wire [31:0] write_data = w_pending_q ? wdata_q : s_axil_wdata_i;
    wire [3:0] write_strb = w_pending_q ? wstrb_q : s_axil_wstrb_i;

    function automatic [31:0] merge_wstrb(
        input [31:0] old_v, input [31:0] new_v, input [3:0] strb
    );
        integer k;
        begin
            merge_wstrb = old_v;
            for (k=0; k<4; k=k+1)
                if (strb[k]) merge_wstrb[k*8 +: 8] = new_v[k*8 +: 8];
        end
    endfunction

    function automatic mapped(input [11:0] a);
        begin
            case (a)
                REG_ID,REG_VERSION,REG_CONTROL,REG_STATUS,REG_TRANSFER_BYTES,
                REG_MODE,REG_STRESS_SEED,REG_DDS_FTW,REG_DDS_CONTROL,
                REG_STREAM_LO,REG_STREAM_HI,REG_CAPTURED,REG_DROPPED,
                REG_BACKPRESSURE: mapped=1'b1;
                default: mapped=1'b0;
            endcase
        end
    endfunction

    function automatic [31:0] read_value(input [11:0] a);
        begin
            case (a)
                REG_ID: read_value=32'h5841_4430; // "XAD0"
                REG_VERSION: read_value=32'h0001_0000;
                REG_STATUS: read_value=status_i;
                REG_TRANSFER_BYTES: read_value=transfer_bytes_o;
                REG_MODE: read_value=mode_o;
                REG_STRESS_SEED: read_value=stress_seed_o;
                REG_DDS_FTW: read_value={4'd0,dds_ftw_o};
                REG_DDS_CONTROL: read_value={31'd0,dds_triangle_o};
                REG_STREAM_LO: read_value=stream_bytes_i[31:0];
                REG_STREAM_HI: read_value=stream_bytes_i[63:32];
                REG_CAPTURED: read_value=captured_samples_i;
                REG_DROPPED: read_value=dropped_samples_i;
                REG_BACKPRESSURE: read_value=backpressure_cycles_i;
                default: read_value=32'd0;
            endcase
        end
    endfunction

    always_comb begin
        s_axil_awready_o = !aw_pending_q && !s_axil_bvalid_o;
        s_axil_wready_o  = !w_pending_q && !s_axil_bvalid_o;
        s_axil_arready_o = !s_axil_rvalid_o;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            aw_pending_q<=0; w_pending_q<=0; awaddr_q<=0; wdata_q<=0; wstrb_q<=0;
            s_axil_bresp_o<=0; s_axil_bvalid_o<=0;
            s_axil_rdata_o<=0; s_axil_rresp_o<=0; s_axil_rvalid_o<=0;
            start_pulse_o<=0; clear_pulse_o<=0; dds_apply_pulse_o<=0;
            transfer_bytes_o<=32'd4096; mode_o<=32'd0;
            stress_seed_o<=32'd0; dds_ftw_o<=28'd0; dds_triangle_o<=1'b0;
        end else begin
            start_pulse_o<=0; clear_pulse_o<=0; dds_apply_pulse_o<=0;
            if (aw_fire) begin aw_pending_q<=1; awaddr_q<=s_axil_awaddr_i[11:0]; end
            if (w_fire) begin w_pending_q<=1; wdata_q<=s_axil_wdata_i; wstrb_q<=s_axil_wstrb_i; end
            if (write_commit) begin
                aw_pending_q<=0; w_pending_q<=0; s_axil_bvalid_o<=1;
                s_axil_bresp_o<=mapped(write_addr) ? 2'b00 : 2'b10;
                case (write_addr)
                    REG_CONTROL: if (write_strb[0]) begin
                        start_pulse_o<=write_data[0]; clear_pulse_o<=write_data[1];
                    end
                    REG_TRANSFER_BYTES: transfer_bytes_o<=merge_wstrb(transfer_bytes_o,write_data,write_strb);
                    REG_MODE: mode_o<=merge_wstrb(mode_o,write_data,write_strb);
                    REG_STRESS_SEED: stress_seed_o<=merge_wstrb(stress_seed_o,write_data,write_strb);
                    REG_DDS_FTW: dds_ftw_o<=merge_wstrb({4'd0,dds_ftw_o},write_data,write_strb);
                    REG_DDS_CONTROL: if (write_strb[0]) begin
                        dds_triangle_o<=write_data[0]; dds_apply_pulse_o<=write_data[1];
                    end
                    default: begin end
                endcase
            end else if (s_axil_bvalid_o && s_axil_bready_i) s_axil_bvalid_o<=0;
            if (s_axil_arvalid_i && s_axil_arready_o) begin
                s_axil_rdata_o<=read_value(s_axil_araddr_i[11:0]);
                s_axil_rresp_o<=mapped(s_axil_araddr_i[11:0]) ? 2'b00 : 2'b10;
                s_axil_rvalid_o<=1;
            end else if (s_axil_rvalid_o && s_axil_rready_i) s_axil_rvalid_o<=0;
        end
    end
endmodule
`default_nettype wire
