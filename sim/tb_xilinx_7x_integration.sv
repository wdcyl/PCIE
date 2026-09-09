`timescale 1ns/1ps
`default_nettype none

module tb_xilinx_7x_integration;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    logic clear_stats;
    logic [63:0] rx_data;
    logic [7:0] rx_keep;
    logic rx_valid;
    wire rx_ready;
    logic rx_last;
    logic [21:0] rx_user;
    wire rx_np_ok, rx_np_req;
    wire [255:0] packet_rx_data;
    wire [31:0] packet_rx_keep;
    wire packet_rx_valid, packet_rx_last, packet_rx_bar0;
    logic packet_rx_ready;

    logic [255:0] packet_tx_data;
    logic [31:0] packet_tx_keep;
    logic packet_tx_valid;
    wire packet_tx_ready;
    wire [63:0] tx_data;
    wire [7:0] tx_keep;
    wire tx_valid, tx_last;
    logic tx_ready;
    wire [3:0] tx_user;
    wire [31:0] rx_drop_count, tx_error_count;

    logic link_up, irq_pending, msi_enable, cfg_interrupt_rdy;
    wire cfg_interrupt, cfg_interrupt_assert, cfg_interrupt_stat;
    wire [7:0] cfg_interrupt_di;
    wire [4:0] cfg_interrupt_msgnum;
    wire msi_request_active;
    wire [31:0] msi_sent_count;

    integer checks = 0;
    integer failures = 0;

    xilinx_7x_axis_bridge_64 u_bridge (
        .clk_i(clk), .rst_ni(rst_n), .clear_stats_i(clear_stats),
        .m_axis_rx_tdata_i(rx_data), .m_axis_rx_tkeep_i(rx_keep),
        .m_axis_rx_tvalid_i(rx_valid), .m_axis_rx_tready_o(rx_ready),
        .m_axis_rx_tlast_i(rx_last), .m_axis_rx_tuser_i(rx_user),
        .rx_np_ok_o(rx_np_ok), .rx_np_req_o(rx_np_req),
        .rx_tlp_data_o(packet_rx_data), .rx_tlp_keep_o(packet_rx_keep),
        .rx_tlp_valid_o(packet_rx_valid), .rx_tlp_ready_i(packet_rx_ready),
        .rx_tlp_last_o(packet_rx_last), .rx_tlp_bar0_hit_o(packet_rx_bar0),
        .tx_tlp_data_i(packet_tx_data), .tx_tlp_keep_i(packet_tx_keep),
        .tx_tlp_valid_i(packet_tx_valid), .tx_tlp_ready_o(packet_tx_ready),
        .s_axis_tx_tdata_o(tx_data), .s_axis_tx_tkeep_o(tx_keep),
        .s_axis_tx_tvalid_o(tx_valid), .s_axis_tx_tready_i(tx_ready),
        .s_axis_tx_tlast_o(tx_last), .s_axis_tx_tuser_o(tx_user),
        .rx_drop_count_o(rx_drop_count),
        .tx_format_error_count_o(tx_error_count)
    );

    xilinx_7x_msi_controller u_msi (
        .clk_i(clk), .rst_ni(rst_n), .link_up_i(link_up),
        .irq_pending_i(irq_pending),
        .cfg_interrupt_msienable_i(msi_enable),
        .cfg_interrupt_rdy_i(cfg_interrupt_rdy),
        .cfg_interrupt_o(cfg_interrupt),
        .cfg_interrupt_assert_o(cfg_interrupt_assert),
        .cfg_interrupt_di_o(cfg_interrupt_di),
        .cfg_interrupt_stat_o(cfg_interrupt_stat),
        .cfg_pciecap_interrupt_msgnum_o(cfg_interrupt_msgnum),
        .request_active_o(msi_request_active),
        .msi_sent_count_o(msi_sent_count)
    );

    task automatic check(input logic condition, input [8*96-1:0] message);
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task automatic send_rx_beat(
        input logic [63:0] data,
        input logic [7:0] keep,
        input logic last,
        input logic [21:0] user
    );
        begin
            @(negedge clk);
            rx_data = data;
            rx_keep = keep;
            rx_last = last;
            rx_user = user;
            rx_valid = 1'b1;
            while (!rx_ready)
                @(negedge clk);
            @(negedge clk);
            rx_valid = 1'b0;
            rx_last = 1'b0;
            rx_user = 22'd0;
        end
    endtask

    task automatic send_tx_packet(
        input logic [31:0] keep,
        input integer expected_beats
    );
        integer beat;
        logic [63:0] held_data;
        logic [7:0] held_keep;
        logic held_last;
        begin
            @(negedge clk);
            packet_tx_data = {
                64'hffeeddccbbaa9988,
                64'hfedcba9876543210,
                64'hdeadbeefcafef00d,
                64'h00ffeeddccbbaa99
            };
            packet_tx_keep = keep;
            packet_tx_valid = 1'b1;
            while (!packet_tx_ready)
                @(negedge clk);
            @(negedge clk);
            packet_tx_valid = 1'b0;

            tx_ready = 1'b0;
            while (!tx_valid)
                @(negedge clk);
            held_data = tx_data;
            held_keep = tx_keep;
            held_last = tx_last;
            repeat (2) begin
                @(negedge clk);
                check(tx_valid, "TX valid dropped during backpressure");
                check(tx_data == held_data, "TX data changed during backpressure");
                check(tx_keep == held_keep, "TX keep changed during backpressure");
                check(tx_last == held_last, "TX last changed during backpressure");
            end

            tx_ready = 1'b1;
            for (beat = 0; beat < expected_beats; beat = beat + 1) begin
                check(tx_valid, "TX packet ended before expected beat count");
                check(tx_data == packet_tx_data[beat * 64 +: 64],
                      "TX data beat ordering mismatch");
                check(tx_keep == packet_tx_keep[beat * 8 +: 8],
                      "TX keep beat mismatch");
                check(tx_last == (beat == expected_beats - 1),
                      "TX last asserted on wrong beat");
                check(tx_user == 4'b0000, "TX tuser must be zero");
                @(negedge clk);
            end
            check(!tx_valid, "TX valid remained asserted after final beat");
            tx_ready = 1'b0;
        end
    endtask

    initial begin
        clear_stats = 0;
        rx_data = 0;
        rx_keep = 0;
        rx_valid = 0;
        rx_last = 0;
        rx_user = 0;
        packet_rx_ready = 0;
        packet_tx_data = 0;
        packet_tx_keep = 0;
        packet_tx_valid = 0;
        tx_ready = 0;
        link_up = 0;
        irq_pending = 0;
        msi_enable = 0;
        cfg_interrupt_rdy = 0;

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // RX BAR0 aggregation, ordering and backpressure.
        send_rx_beat(64'h0706050403020100, 8'hff, 0, 22'h000004);
        send_rx_beat(64'h0f0e0d0c0b0a0908, 8'hff, 1, 22'h000000);
        check(packet_rx_valid, "BAR0 RX packet was not delivered");
        check(packet_rx_bar0, "BAR0 hit was not retained across RX packet");
        check(packet_rx_last, "canonical RX last must be asserted");
        check(packet_rx_keep == 32'h0000ffff, "RX keep aggregation mismatch");
        check(packet_rx_data[127:0] ==
              128'h0f0e0d0c0b0a0908_0706050403020100,
              "RX DWORD/byte ordering mismatch");
        check(!rx_ready && !rx_np_ok && !rx_np_req,
              "RX backpressure was not propagated while packet pending");
        repeat (2) begin
            @(negedge clk);
            check(packet_rx_valid, "RX valid dropped under backpressure");
        end
        packet_rx_ready = 1;
        @(negedge clk);
        packet_rx_ready = 0;
        check(!packet_rx_valid, "RX packet did not retire after ready");

        // Non-BAR traffic is filtered, malformed/oversize traffic is counted.
        send_rx_beat(64'h1122334455667788, 8'hff, 1, 22'd0);
        check(!packet_rx_valid, "non-BAR0 packet reached application");
        check(rx_drop_count == 0, "non-BAR0 packet counted as malformed");
        send_rx_beat(64'h1, 8'h0f, 0, 22'h000004);
        send_rx_beat(64'h2, 8'h0f, 1, 22'h000004);
        check(rx_drop_count == 1, "malformed RX packet count mismatch");
        send_rx_beat(64'h3, 8'hff, 1, 22'h000006);
        check(rx_drop_count == 2 && !packet_rx_valid,
              "poisoned RX packet was not dropped");
        send_rx_beat(64'h4, 8'hff, 1, 22'h000005);
        check(rx_drop_count == 3 && !packet_rx_valid,
              "ECRC-error RX packet was not dropped");
        send_rx_beat(64'h10, 8'hff, 0, 22'h000004);
        send_rx_beat(64'h11, 8'hff, 0, 22'd0);
        send_rx_beat(64'h12, 8'hff, 0, 22'd0);
        send_rx_beat(64'h13, 8'hff, 0, 22'd0);
        send_rx_beat(64'h14, 8'h0f, 1, 22'd0);
        check(rx_drop_count == 4, "oversize RX packet count mismatch");
        check(!packet_rx_valid, "oversize RX packet was delivered");

        // All packet byte lengths accepted by the canonical adapter.
        send_tx_packet(32'h00000fff, 2);
        send_tx_packet(32'h0000ffff, 2);
        send_tx_packet(32'h000fffff, 3);
        send_tx_packet(32'h00ffffff, 3);
        send_tx_packet(32'h0fffffff, 4);
        send_tx_packet(32'hffffffff, 4);

        @(negedge clk);
        packet_tx_keep = 32'h000000ff;
        packet_tx_valid = 1;
        @(negedge clk);
        packet_tx_valid = 0;
        @(negedge clk);
        check(tx_error_count == 1, "invalid TX keep was not counted");
        check(!tx_valid, "invalid TX packet reached AXI output");
        clear_stats = 1;
        @(negedge clk);
        clear_stats = 0;
        @(negedge clk);
        check(rx_drop_count == 0 && tx_error_count == 0,
              "bridge statistics did not clear");

        // MSI request is gated, held through backpressure and one-shot until
        // the sticky IRQ pending source is cleared by software.
        irq_pending = 1;
        repeat (2) @(negedge clk);
        check(!cfg_interrupt, "MSI requested while link/MSI disabled");
        link_up = 1;
        repeat (2) @(negedge clk);
        check(!cfg_interrupt, "MSI requested while MSI disabled");
        msi_enable = 1;
        @(negedge clk);
        check(cfg_interrupt && msi_request_active,
              "MSI request did not start");
        repeat (3) begin
            @(negedge clk);
            check(cfg_interrupt, "MSI request was not held until ready");
        end
        check(!cfg_interrupt_assert && cfg_interrupt_di == 0 &&
              !cfg_interrupt_stat && cfg_interrupt_msgnum == 0,
              "single-vector MSI sideband values are wrong");
        cfg_interrupt_rdy = 1;
        @(negedge clk);
        cfg_interrupt_rdy = 0;
        check(!cfg_interrupt && msi_sent_count == 1,
              "MSI ready handshake was not counted");
        repeat (3) @(negedge clk);
        check(!cfg_interrupt && msi_sent_count == 1,
              "MSI repeated before pending clear");
        irq_pending = 0;
        @(negedge clk);
        irq_pending = 1;
        @(negedge clk);
        check(cfg_interrupt, "MSI did not rearm after pending clear");
        cfg_interrupt_rdy = 1;
        @(negedge clk);
        cfg_interrupt_rdy = 0;
        check(msi_sent_count == 2, "second MSI was not counted");

        if (failures == 0) begin
            $display("PASS: %0d Xilinx 7-Series bridge/MSI checks", checks);
            $finish;
        end
        $fatal(1, "FAIL: %0d of %0d checks failed", failures, checks);
    end

    initial begin
        #100000;
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
