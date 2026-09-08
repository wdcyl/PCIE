`timescale 1ns/1ps

//////////////////////////////////////////////////////////////////////////////
// Card-to-host DMA packetizer
//
// Converts a stream of 16-bit FIFO samples into posted PCIe MWr64 TLPs.
// The output interface carries one complete TLP in one 256-bit beat:
//   tlp_data[ 31:  0] = DW0
//   tlp_data[ 63: 32] = DW1
//   tlp_data[ 95: 64] = DW2 (address[63:32])
//   tlp_data[127: 96] = DW3 (address[31:2], 2'b00)
//   tlp_data[255:128] = payload, first sample in bits [143:128]
//
// host_addr must be DWORD aligned.  A packet contains at most eight samples
// (four payload DWORDs) and is shortened when required to avoid crossing a
// 4-KiB PCIe request boundary.
//////////////////////////////////////////////////////////////////////////////

module c2h_dma_engine (
    input  wire         pcie_clk,
    input  wire         rst,

    input  wire         start,
    input  wire         clear,
    input  wire [63:0]  host_addr,
    input  wire [31:0]  sample_count,
    input  wire [15:0]  requester_id,

    // Synchronous FIFO read request/response interface.  At most one read is
    // outstanding. fifo_rd_valid qualifies fifo_rd_data.
    input  wire [15:0]  fifo_rd_data,
    input  wire         fifo_empty,
    input  wire         fifo_rd_valid,
    output reg          fifo_rd_en,

    // One complete MWr64 TLP per beat.  Header and payload are DWORD aligned,
    // so tlp_keep marks complete DWORDs; byte enables carry partial-sample
    // validity for the final odd sample.
    output reg  [255:0] tlp_data,
    output reg  [31:0]  tlp_keep,
    output reg          tlp_valid,
    input  wire         tlp_ready,

    output reg          busy,
    output reg          done,
    output reg          irq_pending,
    output reg  [31:0]  packets_sent,
    output reg  [63:0]  bytes_sent
);

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_FILL = 2'd1;
    localparam [1:0] STATE_SEND = 2'd2;

    reg [1:0]   state;
    reg [63:0]  current_addr;
    reg [31:0]  samples_remaining;
    reg [3:0]   packet_target_samples;
    reg [3:0]   packet_sample_count;
    reg [127:0] payload_buf;
    reg         fifo_read_pending;

    reg [127:0] payload_with_fifo_data;

    // Select the next packet size.  In addition to the four-DWORD payload
    // limit, PCIe Memory Requests must not cross a 4-KiB boundary.
    function automatic [3:0] choose_packet_samples;
        input [31:0] remaining;
        input [63:0] address;
        integer bytes_to_boundary;
        integer samples_to_boundary;
        integer selected;
        begin
            bytes_to_boundary = 4096 - address[11:0];
            samples_to_boundary = bytes_to_boundary / 2;

            selected = (remaining > 8) ? 8 : remaining;
            if (selected > samples_to_boundary)
                selected = samples_to_boundary;

            choose_packet_samples = selected[3:0];
        end
    endfunction

    function automatic [9:0] payload_length_dw;
        input [3:0] samples;
        begin
            payload_length_dw = (samples + 1) >> 1;
        end
    endfunction

    function automatic [3:0] first_byte_enable;
        input [3:0] samples;
        begin
            if (samples == 1)
                first_byte_enable = 4'b0011;
            else
                first_byte_enable = 4'b1111;
        end
    endfunction

    function automatic [3:0] last_byte_enable;
        input [3:0] samples;
        reg [9:0] length_dw;
        begin
            length_dw = payload_length_dw(samples);
            if (length_dw == 1)
                last_byte_enable = 4'b0000;
            else if (samples[0])
                last_byte_enable = 4'b0011;
            else
                last_byte_enable = 4'b1111;
        end
    endfunction

    function automatic [31:0] make_tkeep;
        input [3:0] samples;
        integer valid_bytes;
        integer i;
        begin
            // TLP byte enables, not TKEEP, identify invalid bytes within the
            // final payload DWORD.  Therefore every transmitted DWORD is kept.
            valid_bytes = 16 + (payload_length_dw(samples) * 4);
            make_tkeep = 32'b0;
            for (i = 0; i < 32; i = i + 1) begin
                if (i < valid_bytes)
                    make_tkeep[i] = 1'b1;
            end
        end
    endfunction

    function automatic [255:0] make_mwr64_tlp;
        input [63:0]  address;
        input [15:0]  req_id;
        input [3:0]   samples;
        input [127:0] payload;
        reg [31:0] dw0;
        reg [31:0] dw1;
        reg [31:0] dw2;
        reg [31:0] dw3;
        reg [255:0] packet;
        begin
            dw0 = 32'b0;
            dw0[31:29] = 3'b011;       // Fmt: 4-DW header with data
            dw0[28:24] = 5'b00000;     // Type: Memory Request
            dw0[9:0]   = payload_length_dw(samples);

            dw1 = 32'b0;
            dw1[31:16] = req_id;
            dw1[15:8]  = 8'h00;        // Tag is unused for posted writes
            dw1[7:4]   = last_byte_enable(samples);
            dw1[3:0]   = first_byte_enable(samples);

            dw2 = address[63:32];
            dw3 = {address[31:2], 2'b00};

            packet = 256'b0;
            packet[127:0]   = {dw3, dw2, dw1, dw0};
            packet[255:128] = payload;
            make_mwr64_tlp = packet;
        end
    endfunction

    // Include the returning FIFO word when assembling the packet on the cycle
    // that the final requested sample arrives.
    always @(*) begin
        payload_with_fifo_data = payload_buf;
        if (packet_sample_count < 8)
            payload_with_fifo_data[(packet_sample_count * 16) +: 16] =
                fifo_rd_data;
    end

    always @(posedge pcie_clk) begin
        if (rst) begin
            state                  <= STATE_IDLE;
            current_addr           <= 64'b0;
            samples_remaining      <= 32'b0;
            packet_target_samples  <= 4'b0;
            packet_sample_count    <= 4'b0;
            payload_buf            <= 128'b0;
            fifo_read_pending      <= 1'b0;
            fifo_rd_en             <= 1'b0;
            tlp_data               <= 256'b0;
            tlp_keep               <= 32'b0;
            tlp_valid              <= 1'b0;
            busy                   <= 1'b0;
            done                   <= 1'b0;
            irq_pending            <= 1'b0;
            packets_sent           <= 32'b0;
            bytes_sent             <= 64'b0;
        end else if (clear) begin
            state                  <= STATE_IDLE;
            current_addr           <= 64'b0;
            samples_remaining      <= 32'b0;
            packet_target_samples  <= 4'b0;
            packet_sample_count    <= 4'b0;
            payload_buf            <= 128'b0;
            fifo_read_pending      <= 1'b0;
            fifo_rd_en             <= 1'b0;
            tlp_data               <= 256'b0;
            tlp_keep               <= 32'b0;
            tlp_valid              <= 1'b0;
            busy                   <= 1'b0;
            done                   <= 1'b0;
            irq_pending            <= 1'b0;
            packets_sent           <= 32'b0;
            bytes_sent             <= 64'b0;
        end else begin
            fifo_rd_en <= 1'b0;

            // New commands are accepted only while idle.  Starting a command
            // also acknowledges the previous sticky done/IRQ indications.
            if (start && !busy) begin
                current_addr          <= host_addr;
                samples_remaining     <= sample_count;
                packet_target_samples <= choose_packet_samples(
                    sample_count, host_addr);
                packet_sample_count   <= 4'b0;
                payload_buf           <= 128'b0;
                fifo_read_pending     <= 1'b0;
                tlp_valid             <= 1'b0;
                done                  <= 1'b0;
                irq_pending           <= 1'b0;

                if (sample_count == 0) begin
                    state       <= STATE_IDLE;
                    busy        <= 1'b0;
                    done        <= 1'b1;
                    irq_pending <= 1'b1;
                end else begin
                    state <= STATE_FILL;
                    busy  <= 1'b1;
                end
            end else begin
                case (state)
                    STATE_IDLE: begin
                        busy      <= 1'b0;
                        tlp_valid <= 1'b0;
                    end

                    STATE_FILL: begin
                        // Issue at most one FIFO read at a time.  This supports
                        // synchronous FIFOs with arbitrary response latency.
                        if (!fifo_read_pending &&
                            (packet_sample_count < packet_target_samples) &&
                            !fifo_empty) begin
                            fifo_rd_en        <= 1'b1;
                            fifo_read_pending <= 1'b1;
                        end

                        if (fifo_read_pending && fifo_rd_valid) begin
                            fifo_read_pending <= 1'b0;
                            payload_buf[(packet_sample_count * 16) +: 16]
                                <= fifo_rd_data;
                            packet_sample_count <= packet_sample_count + 1'b1;
                            samples_remaining   <= samples_remaining - 1'b1;

                            if ((packet_sample_count + 1'b1) ==
                                packet_target_samples) begin
                                tlp_data <= make_mwr64_tlp(
                                    current_addr,
                                    requester_id,
                                    packet_target_samples,
                                    payload_with_fifo_data);
                                tlp_keep  <= make_tkeep(packet_target_samples);
                                tlp_valid <= 1'b1;
                                state     <= STATE_SEND;
                            end
                        end
                    end

                    STATE_SEND: begin
                        // No packet fields change in this state unless the
                        // valid/ready handshake completes, so backpressure is
                        // safe for an arbitrary number of cycles.
                        if (tlp_valid && tlp_ready) begin
                            tlp_valid    <= 1'b0;
                            packets_sent <= packets_sent + 1'b1;
                            bytes_sent   <= bytes_sent +
                                (packet_target_samples * 2);

                            if (samples_remaining == 0) begin
                                state       <= STATE_IDLE;
                                busy        <= 1'b0;
                                done        <= 1'b1;
                                irq_pending <= 1'b1;
                            end else begin
                                current_addr <= current_addr +
                                    (packet_target_samples * 2);
                                packet_target_samples <= choose_packet_samples(
                                    samples_remaining,
                                    current_addr + (packet_target_samples * 2));
                                packet_sample_count <= 4'b0;
                                payload_buf         <= 128'b0;
                                state               <= STATE_FILL;
                            end
                        end
                    end

                    default: begin
                        state             <= STATE_IDLE;
                        fifo_read_pending <= 1'b0;
                        tlp_valid         <= 1'b0;
                        busy              <= 1'b0;
                    end
                endcase
            end
        end
    end

endmodule
