`timescale 1ns/1ps
`default_nettype none

// 7-series XADC hard-macro wrapper.  The sequencer continuously converts
// dedicated VP/VN (channel 3); each result is exposed as an unsigned 12-bit code.
module xadc_sampler (
    input wire dclk_i,
    input wire rst_ni,
    input wire vp_i,
    input wire vn_i,
    output logic [11:0] sample_o,
    output logic sample_valid_o,
    output wire alarm_o,
    output wire busy_o
);
    wire [15:0] do_bus;
    wire drdy, eoc, eos;
    wire [4:0] channel;
    wire [7:0] alarm;
    wire ot;
    wire jtagbusy, jtaglocked, jtagmodified, muxaddr;

    XADC #(
        .INIT_40(16'h0000),
        .INIT_41(16'h2ef0),       // continuous sequencer mode
        .INIT_42(16'h0500),       // 125 MHz / 5 = 25 MHz ADC clock
        .INIT_48(16'h0800),       // CHSEL bit 11: dedicated VP/VN channel
        .INIT_49(16'h0000),
        .INIT_4A(16'h0000), .INIT_4B(16'h0000),
        .INIT_4C(16'h0000), .INIT_4D(16'h0000),
        .INIT_4E(16'h0000), .INIT_4F(16'h0000),
        .SIM_DEVICE("7SERIES")
    ) u_xadc (
        .DCLK(dclk_i), .RESET(!rst_ni),
        .DEN(eoc), .DWE(1'b0), .DADDR({2'b00,channel}), .DI(16'd0),
        .DO(do_bus), .DRDY(drdy), .EOC(eoc), .EOS(eos),
        .CHANNEL(channel), .BUSY(busy_o), .ALM(alarm), .OT(ot),
        .VP(vp_i), .VN(vn_i), .VAUXP(16'd0), .VAUXN(16'd0),
        .CONVST(1'b0), .CONVSTCLK(1'b0),
        .JTAGBUSY(jtagbusy), .JTAGLOCKED(jtaglocked),
        .JTAGMODIFIED(jtagmodified), .MUXADDR(muxaddr)
    );

    always_ff @(posedge dclk_i or negedge rst_ni) begin
        if (!rst_ni) begin sample_o<=0; sample_valid_o<=0; end
        else begin
            sample_valid_o <= drdy && (channel==5'd3);
            if (drdy && (channel==5'd3)) sample_o <= do_bus[15:4];
        end
    end

    assign alarm_o = |alarm | ot;
    wire _unused = &{1'b0,eos,jtagbusy,jtaglocked,jtagmodified,muxaddr};
endmodule
`default_nettype wire
