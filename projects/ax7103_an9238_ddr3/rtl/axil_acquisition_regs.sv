`timescale 1ns/1ps
`default_nettype none

// AXI4-Lite register block used by the PC to control acquisition and AD9833.
//
// Design notes:
//   1. AXI write-address and write-data channels may arrive independently.
//      Each channel is held in a one-entry register until both are available.
//   2. START, CLEAR and DDS_APPLY are one-clock pulses, not stored bits.
//   3. Ordinary configuration registers honor AXI WSTRB byte enables.
module axil_acquisition_regs #(
    parameter integer ADDR_WIDTH = 32
) (
    input  wire                  clk_i,
    input  wire                  rst_ni,

    // AXI4-Lite write-address channel.
    input  wire [ADDR_WIDTH-1:0] s_axil_awaddr_i,
    input  wire                  s_axil_awvalid_i,
    output logic                 s_axil_awready_o,

    // AXI4-Lite write-data channel.
    input  wire [31:0]           s_axil_wdata_i,
    input  wire [3:0]            s_axil_wstrb_i,
    input  wire                  s_axil_wvalid_i,
    output logic                 s_axil_wready_o,

    // AXI4-Lite write-response channel.
    output logic [1:0]           s_axil_bresp_o,
    output logic                 s_axil_bvalid_o,
    input  wire                  s_axil_bready_i,

    // AXI4-Lite read-address channel.
    input  wire [ADDR_WIDTH-1:0] s_axil_araddr_i,
    input  wire                  s_axil_arvalid_i,
    output logic                 s_axil_arready_o,

    // AXI4-Lite read-data channel.
    output logic [31:0]           s_axil_rdata_o,
    output logic [1:0]            s_axil_rresp_o,
    output logic                  s_axil_rvalid_o,
    input  wire                   s_axil_rready_i,

    // Runtime status and counters supplied by the acquisition core.
    input  wire [31:0]            status_i,
    input  wire [31:0]            captured_pairs_i,
    input  wire [63:0]            bytes_written_i,

    // Acquisition control and configuration outputs.
    output logic                  start_pulse_o,
    output logic                  clear_pulse_o,
    output logic [31:0]           capture_bytes_o,
    output logic [31:0]           buffer_base_o,
    output logic [31:0]           mode_o,
    output logic [31:0]           test_seed_o,

    // AD9833 control outputs.
    output logic                  dds_apply_pulse_o,
    output logic [27:0]           dds_ftw_o,
    output logic                  dds_triangle_o
);

    // ---------------------------------------------------------------------
    // Register address map. Only address bits [11:0] are decoded because the
    // block occupies one 4-KiB AXI-Lite aperture.
    // ---------------------------------------------------------------------
    localparam logic [11:0] REG_ID            = 12'h000;
    localparam logic [11:0] REG_VERSION       = 12'h004;
    localparam logic [11:0] REG_CONTROL       = 12'h008;
    localparam logic [11:0] REG_STATUS        = 12'h00c;
    localparam logic [11:0] REG_CAPTURE_BYTES = 12'h010;
    localparam logic [11:0] REG_BUFFER_BASE   = 12'h014;
    localparam logic [11:0] REG_MODE          = 12'h018;
    localparam logic [11:0] REG_TEST_SEED     = 12'h01c;
    localparam logic [11:0] REG_CAPTURED      = 12'h020;
    localparam logic [11:0] REG_WRITTEN_LO    = 12'h024;
    localparam logic [11:0] REG_WRITTEN_HI    = 12'h028;
    localparam logic [11:0] REG_DDS_FTW       = 12'h02c;
    localparam logic [11:0] REG_DDS_CONTROL   = 12'h030;

    localparam logic [31:0] DESIGN_ID      = 32'h4144_3932; // ASCII "AD92"
    localparam logic [31:0] DESIGN_VERSION = 32'h0003_0000; // Version 3.0.0

    // AXI responses used by this block.
    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // One-entry holding registers allow AW and W to arrive in either order.
    logic        aw_pending_q;
    logic [11:0] awaddr_q;
    logic        w_pending_q;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;

    wire aw_fire = s_axil_awvalid_i && s_axil_awready_o;
    wire w_fire  = s_axil_wvalid_i  && s_axil_wready_o;

    // A write is committed as soon as both an address and data are available.
    wire write_commit = !s_axil_bvalid_o &&
                        (aw_pending_q || aw_fire) &&
                        (w_pending_q  || w_fire);

    // Select held values when a channel arrived in an earlier clock cycle;
    // otherwise use the value being accepted in the current cycle.
    wire [11:0] write_addr = aw_pending_q ? awaddr_q : s_axil_awaddr_i[11:0];
    wire [31:0] write_data = w_pending_q  ? wdata_q  : s_axil_wdata_i;
    wire [3:0]  write_strb = w_pending_q  ? wstrb_q  : s_axil_wstrb_i;

    // Apply AXI WSTRB byte enables. Bytes whose strobe bit is zero retain
    // their previous value.
    function automatic [31:0] merge_wstrb(
        input [31:0] old_value,
        input [31:0] new_value,
        input [3:0]  byte_strobe
    );
        integer byte_index;
        begin
            merge_wstrb = old_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                if (byte_strobe[byte_index]) begin
                    merge_wstrb[byte_index*8 +: 8] =
                        new_value[byte_index*8 +: 8];
                end
            end
        end
    endfunction

    // Return one for every implemented register address. Unmapped accesses
    // receive an AXI SLVERR response.
    function automatic is_mapped_address(input [11:0] address);
        begin
            case (address)
                REG_ID,
                REG_VERSION,
                REG_CONTROL,
                REG_STATUS,
                REG_CAPTURE_BYTES,
                REG_BUFFER_BASE,
                REG_MODE,
                REG_TEST_SEED,
                REG_CAPTURED,
                REG_WRITTEN_LO,
                REG_WRITTEN_HI,
                REG_DDS_FTW,
                REG_DDS_CONTROL: is_mapped_address = 1'b1;
                default:         is_mapped_address = 1'b0;
            endcase
        end
    endfunction

    // Combinational read multiplexer. Write-only pulse bits read back as zero.
    function automatic [31:0] read_register(input [11:0] address);
        begin
            case (address)
                REG_ID:            read_register = DESIGN_ID;
                REG_VERSION:       read_register = DESIGN_VERSION;
                REG_STATUS:        read_register = status_i;
                REG_CAPTURE_BYTES: read_register = capture_bytes_o;
                REG_BUFFER_BASE:   read_register = buffer_base_o;
                REG_MODE:          read_register = mode_o;
                REG_TEST_SEED:     read_register = test_seed_o;
                REG_CAPTURED:      read_register = captured_pairs_i;
                REG_WRITTEN_LO:    read_register = bytes_written_i[31:0];
                REG_WRITTEN_HI:    read_register = bytes_written_i[63:32];
                REG_DDS_FTW:       read_register = {4'd0, dds_ftw_o};
                REG_DDS_CONTROL:   read_register = {31'd0, dds_triangle_o};
                default:           read_register = 32'd0;
            endcase
        end
    endfunction

    // Backpressure each channel while its holding register or response slot
    // is occupied. The design supports one outstanding read and one write.
    always_comb begin
        s_axil_awready_o = !aw_pending_q && !s_axil_bvalid_o;
        s_axil_wready_o  = !w_pending_q  && !s_axil_bvalid_o;
        s_axil_arready_o = !s_axil_rvalid_o;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // AXI channel state.
            aw_pending_q     <= 1'b0;
            awaddr_q         <= 12'd0;
            w_pending_q      <= 1'b0;
            wdata_q          <= 32'd0;
            wstrb_q          <= 4'd0;
            s_axil_bresp_o   <= AXI_RESP_OKAY;
            s_axil_bvalid_o  <= 1'b0;
            s_axil_rdata_o   <= 32'd0;
            s_axil_rresp_o   <= AXI_RESP_OKAY;
            s_axil_rvalid_o  <= 1'b0;

            // One-cycle command outputs.
            start_pulse_o     <= 1'b0;
            clear_pulse_o     <= 1'b0;
            dds_apply_pulse_o <= 1'b0;

            // Software-visible configuration defaults.
            capture_bytes_o <= 32'h0010_0000; // 1 MiB
            buffer_base_o   <= 32'd0;
            mode_o          <= 32'd0;         // AN9238 source
            test_seed_o     <= 32'd0;
            dds_ftw_o       <= 28'h0a3d70a;   // About 1 MHz at 25-MHz MCLK
            dds_triangle_o  <= 1'b0;          // Sine wave
        end else begin
            // Pulse outputs return low unless the current write sets them.
            start_pulse_o     <= 1'b0;
            clear_pulse_o     <= 1'b0;
            dds_apply_pulse_o <= 1'b0;

            // Capture write address/data channels independently.
            if (aw_fire) begin
                aw_pending_q <= 1'b1;
                awaddr_q     <= s_axil_awaddr_i[11:0];
            end

            if (w_fire) begin
                w_pending_q <= 1'b1;
                wdata_q     <= s_axil_wdata_i;
                wstrb_q     <= s_axil_wstrb_i;
            end

            // Commit one register write after both AW and W are present.
            if (write_commit) begin
                aw_pending_q    <= 1'b0;
                w_pending_q     <= 1'b0;
                s_axil_bvalid_o <= 1'b1;
                s_axil_bresp_o  <= is_mapped_address(write_addr) ?
                                   AXI_RESP_OKAY : AXI_RESP_SLVERR;

                case (write_addr)
                    REG_CONTROL: begin
                        // CONTROL occupies byte lane zero only.
                        if (write_strb[0]) begin
                            start_pulse_o <= write_data[0];
                            clear_pulse_o <= write_data[1];
                        end
                    end

                    REG_CAPTURE_BYTES: begin
                        capture_bytes_o <= merge_wstrb(
                            capture_bytes_o, write_data, write_strb);
                    end

                    REG_BUFFER_BASE: begin
                        buffer_base_o <= merge_wstrb(
                            buffer_base_o, write_data, write_strb);
                    end

                    REG_MODE: begin
                        mode_o <= merge_wstrb(mode_o, write_data, write_strb);
                    end

                    REG_TEST_SEED: begin
                        test_seed_o <= merge_wstrb(
                            test_seed_o, write_data, write_strb);
                    end

                    REG_DDS_FTW: begin
                        // The AD9833 tuning word is 28 bits; upper write bits
                        // are discarded after byte-strobe merging.
                        dds_ftw_o <= merge_wstrb(
                            {4'd0, dds_ftw_o}, write_data, write_strb);
                    end

                    REG_DDS_CONTROL: begin
                        // Bit 0 is stored; bit 1 generates DDS_APPLY pulse.
                        if (write_strb[0]) begin
                            dds_triangle_o  <= write_data[0];
                            dds_apply_pulse_o <= write_data[1];
                        end
                    end

                    // Writes to read-only registers are acknowledged but have
                    // no side effects. Unmapped writes return SLVERR above.
                    default: begin
                    end
                endcase
            end else if (s_axil_bvalid_o && s_axil_bready_i) begin
                s_axil_bvalid_o <= 1'b0;
            end

            // Accept a read only when no previous R response is outstanding.
            if (s_axil_arvalid_i && s_axil_arready_o) begin
                s_axil_rdata_o  <= read_register(s_axil_araddr_i[11:0]);
                s_axil_rresp_o  <= is_mapped_address(s_axil_araddr_i[11:0]) ?
                                   AXI_RESP_OKAY : AXI_RESP_SLVERR;
                s_axil_rvalid_o <= 1'b1;
            end else if (s_axil_rvalid_o && s_axil_rready_i) begin
                s_axil_rvalid_o <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
