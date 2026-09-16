`timescale 1ns/1ps

// Dual-clock FIFO using binary local pointers and Gray-coded CDC pointers.
// DEPTH must be a power of two and at least four entries.
module async_fifo #(
    parameter integer WIDTH = 16,
    parameter integer DEPTH = 1024
) (
    input  wire                         wr_clk,
    input  wire                         wr_rst_n,
    input  wire                         wr_en,
    input  wire [WIDTH-1:0]             wr_data,
    output logic                        wr_full,
    output wire [$clog2(DEPTH+1)-1:0]   wr_level,
    output logic                        wr_overflow,

    input  wire                         rd_clk,
    input  wire                         rd_rst_n,
    input  wire                         rd_en,
    output logic [WIDTH-1:0]            rd_data,
    output logic                        rd_valid,
    output logic                        rd_empty,
    output wire [$clog2(DEPTH+1)-1:0]   rd_level,
    output logic                        rd_underflow
);

    localparam integer ADDR_WIDTH = $clog2(DEPTH);
    localparam integer PTR_WIDTH  = ADDR_WIDTH + 1;

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_WIDTH-1:0] wr_bin;
    logic [PTR_WIDTH-1:0] wr_gray;
    logic [PTR_WIDTH-1:0] wr_bin_next;
    logic [PTR_WIDTH-1:0] wr_gray_next;
    logic                 wr_full_next;

    logic [PTR_WIDTH-1:0] rd_bin;
    logic [PTR_WIDTH-1:0] rd_gray;
    logic [PTR_WIDTH-1:0] rd_bin_next;
    logic [PTR_WIDTH-1:0] rd_gray_next;
    logic                 rd_empty_next;

    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] rd_gray_wr_sync1;
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] rd_gray_wr_sync2;
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] wr_gray_rd_sync1;
    (* ASYNC_REG = "TRUE" *) logic [PTR_WIDTH-1:0] wr_gray_rd_sync2;

    logic [PTR_WIDTH-1:0] rd_bin_wr_sync;
    logic [PTR_WIDTH-1:0] wr_bin_rd_sync;

    function automatic [PTR_WIDTH-1:0] gray_to_bin(
        input [PTR_WIDTH-1:0] gray
    );
        integer index;
        begin
            gray_to_bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (index = PTR_WIDTH-2; index >= 0; index = index - 1)
                gray_to_bin[index] = gray_to_bin[index+1] ^ gray[index];
        end
    endfunction

    always_comb begin
        wr_bin_next  = wr_bin + ((wr_en && !wr_full) ? 1'b1 : 1'b0);
        wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

        // A full FIFO has the next write pointer one complete ring ahead of
        // the synchronized read pointer.  In Gray code this inverts the top
        // two pointer bits and leaves the remaining bits unchanged.
        wr_full_next = (wr_gray_next == {
            ~rd_gray_wr_sync2[PTR_WIDTH-1:PTR_WIDTH-2],
             rd_gray_wr_sync2[PTR_WIDTH-3:0]
        });
    end

    always_comb begin
        rd_bin_next   = rd_bin + ((rd_en && !rd_empty) ? 1'b1 : 1'b0);
        rd_gray_next  = (rd_bin_next >> 1) ^ rd_bin_next;
        rd_empty_next = (rd_gray_next == wr_gray_rd_sync2);
    end

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin      <= '0;
            wr_gray     <= '0;
            wr_full     <= 1'b0;
            wr_overflow <= 1'b0;
        end else begin
            wr_overflow <= wr_en && wr_full;
            wr_bin      <= wr_bin_next;
            wr_gray     <= wr_gray_next;
            wr_full     <= wr_full_next;

            if (wr_en && !wr_full)
                mem[wr_bin[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin       <= '0;
            rd_gray      <= '0;
            rd_empty     <= 1'b1;
            rd_data      <= '0;
            rd_valid     <= 1'b0;
            rd_underflow <= 1'b0;
        end else begin
            rd_valid     <= rd_en && !rd_empty;
            rd_underflow <= rd_en && rd_empty;
            rd_bin       <= rd_bin_next;
            rd_gray      <= rd_gray_next;
            rd_empty     <= rd_empty_next;

            if (rd_en && !rd_empty)
                rd_data <= mem[rd_bin[ADDR_WIDTH-1:0]];
        end
    end

    // Synchronize only Gray-coded pointers between clock domains.
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_wr_sync1 <= '0;
            rd_gray_wr_sync2 <= '0;
        end else begin
            rd_gray_wr_sync1 <= rd_gray;
            rd_gray_wr_sync2 <= rd_gray_wr_sync1;
        end
    end

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_rd_sync1 <= '0;
            wr_gray_rd_sync2 <= '0;
        end else begin
            wr_gray_rd_sync1 <= wr_gray;
            wr_gray_rd_sync2 <= wr_gray_rd_sync1;
        end
    end

    always_comb begin
        rd_bin_wr_sync = gray_to_bin(rd_gray_wr_sync2);
        wr_bin_rd_sync = gray_to_bin(wr_gray_rd_sync2);
    end

    // These levels are conservative snapshots because the remote pointer is
    // delayed by the two-flop synchronizer.  They are intended for monitoring
    // and flow-control thresholds, not exact cross-domain accounting.
    assign wr_level = wr_bin - rd_bin_wr_sync;
    assign rd_level = wr_bin_rd_sync - rd_bin;

`ifndef SYNTHESIS
    initial begin
        if (DEPTH < 4 || (DEPTH & (DEPTH - 1)) != 0)
            $error("async_fifo DEPTH must be a power of two and >= 4");
    end
`endif

endmodule
