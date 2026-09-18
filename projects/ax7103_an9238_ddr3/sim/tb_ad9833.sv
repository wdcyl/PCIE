`timescale 1ns/1ps

module tb_ad9833;
    logic clk=0;
    logic rst_n=0;
    logic apply=0;
    wire busy,done,sclk,fsync_n,sdata;
    integer frame_count=0;
    integer falling_edge_count=0;

    always #5 clk=~clk;

    ad9833_controller #(.CLK_DIV(2)) dut(
        .clk_i(clk),.rst_ni(rst_n),.apply_i(apply),.ftw_i(28'h1234567),
        .triangle_i(1'b0),.busy_o(busy),.done_pulse_o(done),
        .sclk_o(sclk),.fsync_no(fsync_n),.sdata_o(sdata));

    always @(negedge fsync_n) frame_count=frame_count+1;
    always @(negedge sclk) if(!fsync_n) falling_edge_count=falling_edge_count+1;

    initial begin
        repeat(4) @(posedge clk);
        rst_n<=1;
        @(posedge clk);apply<=1;
        @(posedge clk);apply<=0;
        wait(done);
        @(posedge clk);
        if(busy||!fsync_n||frame_count!=5||falling_edge_count!=80)
            $fatal(1,"AD9833 sequence failed: busy=%0d fsync=%0d frames=%0d bits=%0d",
                busy,fsync_n,frame_count,falling_edge_count);
        $display("PASS: AD9833 five-word SPI sequence (%0d falling edges)",falling_edge_count);
        $finish;
    end
endmodule
