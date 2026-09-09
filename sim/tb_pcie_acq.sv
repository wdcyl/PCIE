`timescale 1ns/1ps

module tb_pcie_acq;
    localparam [15:0] HOST_ID = 16'h0100;
    localparam [15:0] EP_ID   = 16'h0200;
    localparam [63:0] HOST_MEM_BASE = 64'h0000_0000_1000_0000;
    localparam integer HOST_MEM_SIZE = 16384;

    reg pcie_clk = 1'b0;
    reg adc_clk = 1'b0;
    reg pcie_rst_n = 1'b0;
    reg adc_rst_n = 1'b0;
    always #2 pcie_clk = ~pcie_clk;
    always #5 adc_clk = ~adc_clk;

    reg [255:0] rx_data;
    reg [31:0] rx_keep;
    reg rx_valid;
    wire rx_ready;
    reg rx_last;
    reg rx_bar0_hit;

    wire [255:0] tx_data;
    wire [31:0] tx_keep;
    wire tx_valid;
    reg tx_ready;
    reg dma_enable;
    wire tx_last;
    wire irq;
    wire [31:0] status;
    wire [31:0] captured_count;
    wire [31:0] dropped_count;

    integer errors = 0;
    integer checks = 0;
    integer cpl_count = 0;
    integer dma_packet_count = 0;
    integer dma_payload_bytes = 0;
    integer ready_mode = 0;
    reg [15:0] ready_lfsr = 16'h5a3c;
    reg [255:0] last_cpl;
    reg stalled_prev;
    reg [255:0] stalled_data;
    reg [31:0] stalled_keep;
    reg [7:0] host_mem [0:HOST_MEM_SIZE-1];

    pcie_acq_top #(
        .FIFO_DEPTH(16),
        .ADC_VALID_DIV(2)
    ) dut (
        .pcie_clk_i(pcie_clk), .pcie_rst_ni(pcie_rst_n),
        .adc_clk_i(adc_clk), .adc_rst_ni(adc_rst_n),
        .s_axis_rx_tdata_i(rx_data), .s_axis_rx_tkeep_i(rx_keep),
        .s_axis_rx_tvalid_i(rx_valid), .s_axis_rx_tready_o(rx_ready),
        .s_axis_rx_tlast_i(rx_last), .s_axis_rx_bar0_hit_i(rx_bar0_hit),
        .m_axis_tx_tdata_o(tx_data), .m_axis_tx_tkeep_o(tx_keep),
        .m_axis_tx_tvalid_o(tx_valid), .m_axis_tx_tready_i(tx_ready),
        .m_axis_tx_tlast_o(tx_last), .completer_id_i(EP_ID),
        .requester_id_i(EP_ID), .dma_enable_i(dma_enable),
        .irq_o(irq), .status_o(status),
        .captured_count_o(captured_count), .dropped_count_o(dropped_count)
    );

    task automatic pass(input string name);
        begin
            checks = checks + 1;
            $display("[PASS] %s", name);
        end
    endtask

    task automatic fail(input string name);
        begin
            checks = checks + 1;
            errors = errors + 1;
            $display("[FAIL] %s", name);
        end
    endtask

    task automatic check32(
        input string name,
        input [31:0] actual,
        input [31:0] expected
    );
        begin
            if (actual === expected)
                pass(name);
            else begin
                fail(name);
                $display("       expected=%08x actual=%08x", expected, actual);
            end
        end
    endtask

    task automatic send_mwr32(
        input [11:0] address,
        input [31:0] data,
        input [3:0] first_be
    );
        reg [255:0] packet;
        begin
            packet = 256'd0;
            packet[31:0]   = 32'h4000_0001;
            packet[63:32]  = {HOST_ID, 8'h00, 4'h0, first_be};
            packet[95:64]  = {20'd0, address[11:2], 2'b00};
            packet[127:96] = data;
            @(negedge pcie_clk);
            rx_data = packet;
            rx_keep = 32'h0000_ffff;
            rx_valid = 1'b1;
            rx_last = 1'b1;
            rx_bar0_hit = 1'b1;
            while (!rx_ready)
                @(negedge pcie_clk);
            @(negedge pcie_clk);
            rx_valid = 1'b0;
            rx_data = 256'd0;
            rx_keep = 32'd0;
        end
    endtask

    task automatic send_unsupported_mwr64;
        reg [255:0] packet;
        begin
            packet = 256'd0;
            packet[31:0]    = 32'h6000_0001;
            packet[63:32]   = {HOST_ID, 8'h00, 4'h0, 4'hf};
            packet[95:64]   = 32'h0000_0000;
            packet[127:96]  = 32'h0000_0200;
            packet[159:128] = 32'hdead_beef;
            @(negedge pcie_clk);
            rx_data = packet;
            rx_keep = 32'h000f_ffff;
            rx_valid = 1'b1;
            rx_last = 1'b1;
            rx_bar0_hit = 1'b1;
            while (!rx_ready)
                @(negedge pcie_clk);
            @(negedge pcie_clk);
            rx_valid = 1'b0;
            rx_data = 256'd0;
            rx_keep = 32'd0;
        end
    endtask

    task automatic send_mrd32(
        input [11:0] address,
        input [7:0] tag
    );
        reg [255:0] packet;
        begin
            packet = 256'd0;
            packet[31:0]  = 32'h0000_0001;
            packet[63:32] = {HOST_ID, tag, 4'h0, 4'hf};
            packet[95:64] = {20'd0, address[11:2], 2'b00};
            @(negedge pcie_clk);
            rx_data = packet;
            rx_keep = 32'h0000_0fff;
            rx_valid = 1'b1;
            rx_last = 1'b1;
            rx_bar0_hit = 1'b1;
            while (!rx_ready)
                @(negedge pcie_clk);
            @(negedge pcie_clk);
            rx_valid = 1'b0;
            rx_data = 256'd0;
            rx_keep = 32'd0;
        end
    endtask

    task automatic bar_read(
        input [11:0] address,
        input [7:0] tag,
        output reg [31:0] value,
        output reg [255:0] packet
    );
        integer before_count;
        integer timeout;
        begin
            before_count = cpl_count;
            send_mrd32(address, tag);
            timeout = 0;
            while ((cpl_count == before_count) && (timeout < 2000)) begin
                @(posedge pcie_clk);
                timeout = timeout + 1;
            end
            @(negedge pcie_clk);
            if (cpl_count == before_count) begin
                fail("BAR read completion timeout");
                value = 32'hxxxx_xxxx;
                packet = 256'd0;
            end else begin
                packet = last_cpl;
                value = last_cpl[127:96];
            end
        end
    endtask

    task automatic wait_dma_done(input integer max_cycles);
        integer count;
        begin
            count = 0;
            while (!status[4] && (count < max_cycles)) begin
                @(posedge pcie_clk);
                count = count + 1;
            end
            if (status[4])
                pass("DMA completed before timeout");
            else
                fail("DMA completion timeout");
        end
    endtask

    task automatic wait_overflow(input integer max_cycles);
        integer count;
        begin
            count = 0;
            while (!status[2] && (count < max_cycles)) begin
                @(posedge pcie_clk);
                count = count + 1;
            end
            if (status[2])
                pass("FIFO overflow detected under sustained backpressure");
            else
                fail("FIFO overflow was not detected");
        end
    endtask

    function automatic [15:0] memory_sample(input integer byte_offset);
        memory_sample = {host_mem[byte_offset+1], host_mem[byte_offset]};
    endfunction

    task automatic check_ramp_region(
        input integer byte_offset,
        input integer sample_total,
        input string name
    );
        integer index;
        reg [15:0] first_value;
        reg [15:0] actual;
        reg region_ok;
        begin
            first_value = memory_sample(byte_offset);
            region_ok = 1'b1;
            for (index = 0; index < sample_total; index = index + 1) begin
                actual = memory_sample(byte_offset + index*2);
                if (actual !== (first_value + index)) begin
                    region_ok = 1'b0;
                    $display("       ramp mismatch index=%0d expected=%04x actual=%04x",
                             index, first_value + index, actual);
                end
            end
            if (region_ok)
                pass(name);
            else
                fail(name);
        end
    endtask

    task automatic consume_dma_tlp(input [255:0] packet);
        integer length_dw;
        integer dw_index;
        integer byte_lane;
        integer payload_byte;
        integer memory_index;
        reg [63:0] address;
        reg [3:0] first_be;
        reg [3:0] last_be;
        reg lane_enabled;
        begin
            length_dw = packet[9:0];
            first_be = packet[35:32];
            last_be = packet[39:36];
            address = {packet[95:64], packet[127:96]};
            address[1:0] = 2'b00;

            if ((address < HOST_MEM_BASE) ||
                ((address - HOST_MEM_BASE + length_dw*4) > HOST_MEM_SIZE)) begin
                fail("DMA address stays inside host memory model");
            end else begin
                for (dw_index = 0; dw_index < length_dw; dw_index = dw_index + 1) begin
                    for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1) begin
                        if (length_dw == 1)
                            lane_enabled = first_be[byte_lane];
                        else if (dw_index == 0)
                            lane_enabled = first_be[byte_lane];
                        else if (dw_index == length_dw-1)
                            lane_enabled = last_be[byte_lane];
                        else
                            lane_enabled = 1'b1;

                        if (lane_enabled) begin
                            payload_byte = dw_index*4 + byte_lane;
                            memory_index = address - HOST_MEM_BASE + payload_byte;
                            host_mem[memory_index] = packet[128 + payload_byte*8 +: 8];
                            dma_payload_bytes = dma_payload_bytes + 1;
                        end
                    end
                end
                dma_packet_count = dma_packet_count + 1;
            end

            if ((address[11:0] + length_dw*4) > 4096)
                fail("DMA packet does not cross a 4 KiB boundary");
        end
    endtask

    always @(negedge pcie_clk) begin
        ready_lfsr <= {ready_lfsr[14:0], ready_lfsr[15] ^ ready_lfsr[13]};
        case (ready_mode)
            1: tx_ready <= ready_lfsr[0] | ready_lfsr[3];
            2: tx_ready <= 1'b0;
            default: tx_ready <= 1'b1;
        endcase
    end

    always @(posedge pcie_clk) begin
        if (!pcie_rst_n) begin
            stalled_prev <= 1'b0;
            stalled_data <= 256'd0;
            stalled_keep <= 32'd0;
        end else begin
            if (stalled_prev) begin
                if (!tx_valid || (tx_data !== stalled_data) || (tx_keep !== stalled_keep))
                    fail("TX packet remains stable while backpressured");
            end
            stalled_prev <= tx_valid && !tx_ready;
            stalled_data <= tx_data;
            stalled_keep <= tx_keep;

            if (tx_valid && tx_ready) begin
                if ((tx_data[31:24] == 8'h4a) || (tx_data[31:24] == 8'h0a)) begin
                    last_cpl <= tx_data;
                    cpl_count <= cpl_count + 1;
                end else if (tx_data[31:24] == 8'h60) begin
                    consume_dma_tlp(tx_data);
                end else begin
                    fail("TX TLP has a supported Fmt/Type");
                end
            end
        end
    end

    integer index;
    integer packets_before;
    integer cpl_before;
    integer bytes_before;
    reg [31:0] read_value;
    reg [255:0] read_packet;

    initial begin
        $dumpfile("build/pcie_acq.vcd");
        $dumpvars(0, tb_pcie_acq);
        rx_data = 0;
        rx_keep = 0;
        rx_valid = 0;
        rx_last = 0;
        rx_bar0_hit = 0;
        tx_ready = 0;
        dma_enable = 1'b1;
        stalled_prev = 0;
        for (index = 0; index < HOST_MEM_SIZE; index = index + 1)
            host_mem[index] = 8'h00;

        repeat (8) @(posedge pcie_clk);
        pcie_rst_n = 1'b1;
        adc_rst_n = 1'b1;
        repeat (12) @(posedge pcie_clk);

        $display("\n=== M1: BAR MRd/MWr and Completion ===");
        bar_read(12'h000, 8'h11, read_value, read_packet);
        check32("DEVICE_ID through MRd/CplD", read_value, 32'h5043_4945);
        check32("CplD Requester ID and Tag", read_packet[95:64] & 32'hffff_ff00,
                {HOST_ID, 8'h11, 8'h00});
        check32("CplD Completer/Status/ByteCount", read_packet[63:32],
                {EP_ID, 3'b000, 1'b0, 12'd4});

        send_mwr32(12'h010, 32'd37, 4'hf);
        bar_read(12'h010, 8'h12, read_value, read_packet);
        check32("BAR register write/read", read_value, 32'd37);

        bar_read(12'h0fc, 8'h13, read_value, read_packet);
        if ((read_packet[31:24] == 8'h0a) &&
            (read_packet[47:45] == 3'b001))
            pass("Unsupported BAR read returns UR Completion");
        else
            fail("Unsupported BAR read returns UR Completion");

        cpl_before = cpl_count;
        send_unsupported_mwr64();
        repeat (20) @(posedge pcie_clk);
        if (cpl_count == cpl_before)
            pass("Unsupported MWr64 remains Posted without Completion");
        else
            fail("Unsupported MWr64 remains Posted without Completion");

        send_mwr32(12'h024, 32'h0000_0004, 4'hf);
        send_mwr32(12'h03c, 32'hffff_ffff, 4'hf);
        send_mwr32(12'h008, 32'h0000_0008, 4'hf);
        repeat (8) @(posedge pcie_clk);
        bar_read(12'h020, 8'h14, read_value, read_packet);
        check32("Clear Stats does not retrigger protocol-error IRQ",
                read_value, 32'd0);

        $display("\n=== PCIe command gating ===");
        send_mwr32(12'h024, 32'h0000_0008, 4'hf);
        dma_enable = 1'b0;
        send_mwr32(12'h008, 32'h0000_0001, 4'hf);
        repeat (8) @(posedge pcie_clk);
        bar_read(12'h020, 8'h15, read_value, read_packet);
        if (read_value[3] && irq && status[8] && !status[0] && !status[3])
            pass("START is rejected until PCIe Bus Master Enable/link gate opens");
        else
            fail("START is rejected until PCIe Bus Master Enable/link gate opens");
        send_mwr32(12'h03c, 32'h0000_0008, 4'hf);
        send_mwr32(12'h008, 32'h0000_0008, 4'hf);
        dma_enable = 1'b1;
        repeat (8) @(posedge pcie_clk);

        $display("\n=== M2/M3: acquisition, FIFO and C2H DMA ===");
        send_mwr32(12'h008, 32'h0000_0008, 4'hf);
        send_mwr32(12'h010, 32'd37, 4'hf);
        send_mwr32(12'h014, 32'd0, 4'hf);
        send_mwr32(12'h018, HOST_MEM_BASE[31:0] + 32'h100, 4'hf);
        send_mwr32(12'h01c, HOST_MEM_BASE[63:32], 4'hf);
        send_mwr32(12'h024, 32'h0000_0007, 4'hf);
        repeat (8) @(posedge adc_clk);
        ready_mode = 1;
        packets_before = dma_packet_count;
        bytes_before = dma_payload_bytes;
        send_mwr32(12'h008, 32'h0000_0001, 4'hf);
        wait_dma_done(20000);
        ready_mode = 0;
        repeat (10) @(posedge pcie_clk);

        if ((captured_count == 37) && (dropped_count == 0))
            pass("37 samples captured without loss");
        else
            fail("37 samples captured without loss");
        if ((dma_packet_count - packets_before) == 5)
            pass("37 samples packetized into five MWr64 TLPs");
        else
            fail("37 samples packetized into five MWr64 TLPs");
        if ((dma_payload_bytes - bytes_before) == 74)
            pass("DMA byte enables preserve odd final sample");
        else
            fail("DMA byte enables preserve odd final sample");
        check_ramp_region(16'h0100, 37, "DMA payload matches consecutive ADC ramp samples");

        bar_read(12'h034, 8'h20, read_value, read_packet);
        check32("DMA byte counter", read_value, 32'd74);
        bar_read(12'h020, 8'h21, read_value, read_packet);
        if (read_value[0] && irq)
            pass("DMA completion sets enabled interrupt");
        else
            fail("DMA completion sets enabled interrupt");
        // Clear both DMA-done and the earlier deliberate UR/error event.
        send_mwr32(12'h03c, 32'hffff_ffff, 4'hf);
        repeat (3) @(posedge pcie_clk);
        if (!irq)
            pass("IRQ_CLEAR write-one-to-clear clears IRQ_STATUS");
        else
            fail("IRQ_CLEAR write-one-to-clear clears IRQ_STATUS");

        $display("\n=== M3: 4 KiB split and backpressure stability ===");
        send_mwr32(12'h008, 32'h0000_0008, 4'hf);
        send_mwr32(12'h010, 32'd12, 4'hf);
        send_mwr32(12'h018, HOST_MEM_BASE[31:0] + 32'h0ff8, 4'hf);
        send_mwr32(12'h01c, HOST_MEM_BASE[63:32], 4'hf);
        repeat (8) @(posedge adc_clk);
        packets_before = dma_packet_count;
        bytes_before = dma_payload_bytes;
        ready_mode = 1;
        send_mwr32(12'h008, 32'h0000_0001, 4'hf);
        wait_dma_done(20000);
        ready_mode = 0;
        repeat (10) @(posedge pcie_clk);
        if ((dma_packet_count - packets_before) == 2)
            pass("DMA splits transfer at 4 KiB boundary");
        else
            fail("DMA splits transfer at 4 KiB boundary");
        if ((dma_payload_bytes - bytes_before) == 24)
            pass("4 KiB boundary transfer preserves byte count");
        else
            fail("4 KiB boundary transfer preserves byte count");
        check_ramp_region(16'h0ff8, 12, "Boundary-split DMA data remains ordered");

        $display("\n=== PCIe Bus Master Enable pause/resume ===");
        send_mwr32(12'h008, 32'h0000_0008, 4'hf);
        send_mwr32(12'h010, 32'd12, 4'hf);
        send_mwr32(12'h018, HOST_MEM_BASE[31:0] + 32'h3000, 4'hf);
        send_mwr32(12'h01c, HOST_MEM_BASE[63:32], 4'hf);
        repeat (8) @(posedge adc_clk);
        packets_before = dma_packet_count;
        ready_mode = 2;
        send_mwr32(12'h008, 32'h0000_0001, 4'hf);
        repeat (100) @(posedge pcie_clk);
        dma_enable = 1'b0;
        ready_mode = 0;
        index = 0;
        while ((dma_packet_count == packets_before) && (index < 1000)) begin
            @(posedge pcie_clk);
            index = index + 1;
        end
        if ((dma_packet_count - packets_before) == 1)
            pass("TLP accepted before BME clear is allowed to complete");
        else
            fail("TLP accepted before BME clear is allowed to complete");
        packets_before = dma_packet_count;
        repeat (200) @(posedge pcie_clk);
        if ((dma_packet_count == packets_before) && status[3])
            pass("No new DMA MWr is launched while BME is clear");
        else
            fail("No new DMA MWr is launched while BME is clear");
        dma_enable = 1'b1;
        wait_dma_done(20000);
        repeat (4) @(posedge pcie_clk);
        check_ramp_region(16'h3000, 12,
                          "DMA resumes without data loss after BME returns");

        $display("\n=== Exception: overflow and recovery ===");
        send_mwr32(12'h008, 32'h0000_0008, 4'hf);
        send_mwr32(12'h010, 32'd64, 4'hf);
        send_mwr32(12'h018, HOST_MEM_BASE[31:0] + 32'h2000, 4'hf);
        send_mwr32(12'h01c, HOST_MEM_BASE[63:32], 4'hf);
        repeat (8) @(posedge adc_clk);
        ready_mode = 2;
        send_mwr32(12'h008, 32'h0000_0001, 4'hf);
        wait_overflow(10000);
        if (dropped_count != 0)
            pass("Dropped-sample counter increments on overflow");
        else
            fail("Dropped-sample counter increments on overflow");
        ready_mode = 0;
        wait_dma_done(40000);
        repeat (10) @(posedge pcie_clk);
        if (status[2])
            pass("Overflow status remains sticky until cleared");
        else
            fail("Overflow status remains sticky until cleared");

        $display("\n=== Regression summary ===");
        $display("checks=%0d errors=%0d cpl=%0d dma_packets=%0d dma_bytes=%0d",
                 checks, errors, cpl_count, dma_packet_count, dma_payload_bytes);
        if (errors == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            $fatal(1, "REGRESSION FAILED: %0d checks failed", errors);
        end
    end
endmodule
