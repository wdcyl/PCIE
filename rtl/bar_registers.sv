`timescale 1ns/1ps
`default_nettype none

// BAR0 register bank used by the control plane of the acquisition design.
// All addresses are byte offsets relative to BAR0.  The block supports
// byte-granular writes; read data is combinational and sampled by the TLP
// endpoint when accepting an MRd.
module bar_registers #(
    parameter logic [31:0] DEVICE_ID = 32'h5043_4945, // "PCIE"
    parameter logic [31:0] VERSION   = 32'h0001_0000
) (
    input  logic          clk_i,
    input  logic          rst_ni,

    input  logic [11:0]   addr_i,
    input  logic          wr_en_i,
    input  logic [31:0]   wr_data_i,
    input  logic [3:0]    wr_strb_i,
    input  logic          rd_en_i,
    output logic [31:0]   rd_data_o,
    output logic          addr_valid_o,

    input  logic [31:0]   status_i,
    input  logic [31:0]   irq_set_i,
    input  logic [31:0]   rx_tlp_count_i,
    input  logic [31:0]   tx_tlp_count_i,
    input  logic [31:0]   error_count_i,
    input  logic [63:0]   byte_count_i,

    output logic          start_pulse_o,
    output logic          clear_stats_pulse_o,
    output logic [31:0]   sample_count_o,
    output logic [31:0]   pattern_o,
    output logic [63:0]   dma_addr_o,
    output logic [31:0]   irq_status_o,
    output logic [31:0]   irq_enable_o,
    output logic          irq_o
);

    localparam logic [11:0] REG_DEVICE_ID     = 12'h000;
    localparam logic [11:0] REG_VERSION       = 12'h004;
    localparam logic [11:0] REG_CONTROL       = 12'h008;
    localparam logic [11:0] REG_STATUS        = 12'h00c;
    localparam logic [11:0] REG_SAMPLE_COUNT  = 12'h010;
    localparam logic [11:0] REG_PATTERN       = 12'h014;
    localparam logic [11:0] REG_DMA_ADDR_LO   = 12'h018;
    localparam logic [11:0] REG_DMA_ADDR_HI   = 12'h01c;
    localparam logic [11:0] REG_IRQ_STATUS    = 12'h020;
    localparam logic [11:0] REG_IRQ_ENABLE    = 12'h024;
    localparam logic [11:0] REG_RX_TLP_COUNT  = 12'h028;
    localparam logic [11:0] REG_TX_TLP_COUNT  = 12'h02c;
    localparam logic [11:0] REG_ERROR_COUNT   = 12'h030;
    localparam logic [11:0] REG_BYTE_COUNT_LO = 12'h034;
    localparam logic [11:0] REG_BYTE_COUNT_HI = 12'h038;
    localparam logic [11:0] REG_IRQ_CLEAR     = 12'h03c;

    logic [31:0] sample_count_q;
    logic [31:0] pattern_q;
    logic [31:0] dma_addr_lo_q;
    logic [31:0] dma_addr_hi_q;
    logic [31:0] irq_status_q;
    logic [31:0] irq_enable_q;
    logic [31:0] irq_clear_mask;

    function automatic logic [31:0] merge_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strb
    );
        integer lane;
        begin
            merge_wstrb = old_value;
            for (lane = 0; lane < 4; lane = lane + 1) begin
                if (strb[lane])
                    merge_wstrb[lane*8 +: 8] = new_value[lane*8 +: 8];
            end
        end
    endfunction

    always_comb begin
        case (addr_i)
            REG_DEVICE_ID,
            REG_VERSION,
            REG_CONTROL,
            REG_STATUS,
            REG_SAMPLE_COUNT,
            REG_PATTERN,
            REG_DMA_ADDR_LO,
            REG_DMA_ADDR_HI,
            REG_IRQ_STATUS,
            REG_IRQ_ENABLE,
            REG_RX_TLP_COUNT,
            REG_TX_TLP_COUNT,
            REG_ERROR_COUNT,
            REG_BYTE_COUNT_LO,
            REG_BYTE_COUNT_HI,
            REG_IRQ_CLEAR:     addr_valid_o = 1'b1;
            default:           addr_valid_o = 1'b0;
        endcase
    end

    always_comb begin
        rd_data_o = 32'h0000_0000;
        if (rd_en_i) begin
            case (addr_i)
                REG_DEVICE_ID:     rd_data_o = DEVICE_ID;
                REG_VERSION:       rd_data_o = VERSION;
                REG_CONTROL:       rd_data_o = 32'h0000_0000;
                REG_STATUS:        rd_data_o = status_i;
                REG_SAMPLE_COUNT:  rd_data_o = sample_count_q;
                REG_PATTERN:       rd_data_o = pattern_q;
                REG_DMA_ADDR_LO:   rd_data_o = dma_addr_lo_q;
                REG_DMA_ADDR_HI:   rd_data_o = dma_addr_hi_q;
                REG_IRQ_STATUS:    rd_data_o = irq_status_q;
                REG_IRQ_ENABLE:    rd_data_o = irq_enable_q;
                REG_RX_TLP_COUNT:  rd_data_o = rx_tlp_count_i;
                REG_TX_TLP_COUNT:  rd_data_o = tx_tlp_count_i;
                REG_ERROR_COUNT:   rd_data_o = error_count_i;
                REG_BYTE_COUNT_LO: rd_data_o = byte_count_i[31:0];
                REG_BYTE_COUNT_HI: rd_data_o = byte_count_i[63:32];
                REG_IRQ_CLEAR:     rd_data_o = 32'h0000_0000;
                default:           rd_data_o = 32'h0000_0000;
            endcase
        end
    end

    always_comb begin
        irq_clear_mask = 32'h0000_0000;
        if (wr_en_i && (addr_i == REG_IRQ_CLEAR)) begin
            if (wr_strb_i[0]) irq_clear_mask[7:0]   = wr_data_i[7:0];
            if (wr_strb_i[1]) irq_clear_mask[15:8]  = wr_data_i[15:8];
            if (wr_strb_i[2]) irq_clear_mask[23:16] = wr_data_i[23:16];
            if (wr_strb_i[3]) irq_clear_mask[31:24] = wr_data_i[31:24];
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            start_pulse_o      <= 1'b0;
            clear_stats_pulse_o<= 1'b0;
            sample_count_q     <= 32'd1024;
            pattern_q          <= 32'd0;
            dma_addr_lo_q      <= 32'd0;
            dma_addr_hi_q      <= 32'd0;
            irq_status_q       <= 32'd0;
            irq_enable_q       <= 32'd0;
        end else begin
            // CONTROL bits are commands and intentionally last exactly one cycle.
            start_pulse_o       <= 1'b0;
            clear_stats_pulse_o <= 1'b0;

            // W1C and hardware set can occur together; a new event wins.
            irq_status_q <= (irq_status_q & ~irq_clear_mask) | irq_set_i;

            if (wr_en_i && addr_valid_o) begin
                case (addr_i)
                    REG_CONTROL: begin
                        if (wr_strb_i[0]) begin
                            start_pulse_o       <= wr_data_i[0];
                            clear_stats_pulse_o <= wr_data_i[3];
                        end
                    end
                    REG_SAMPLE_COUNT:
                        sample_count_q <= merge_wstrb(sample_count_q, wr_data_i, wr_strb_i);
                    REG_PATTERN:
                        pattern_q <= merge_wstrb(pattern_q, wr_data_i, wr_strb_i);
                    REG_DMA_ADDR_LO:
                        dma_addr_lo_q <= merge_wstrb(dma_addr_lo_q, wr_data_i, wr_strb_i);
                    REG_DMA_ADDR_HI:
                        dma_addr_hi_q <= merge_wstrb(dma_addr_hi_q, wr_data_i, wr_strb_i);
                    REG_IRQ_ENABLE:
                        irq_enable_q <= merge_wstrb(irq_enable_q, wr_data_i, wr_strb_i);
                    default: begin
                        // Read-only registers and IRQ_CLEAR require no action here.
                    end
                endcase
            end
        end
    end

    assign sample_count_o = sample_count_q;
    assign pattern_o      = pattern_q;
    assign dma_addr_o     = {dma_addr_hi_q, dma_addr_lo_q};
    assign irq_status_o   = irq_status_q;
    assign irq_enable_o   = irq_enable_q;
    assign irq_o          = |(irq_status_q & irq_enable_q);

endmodule

`default_nettype wire
