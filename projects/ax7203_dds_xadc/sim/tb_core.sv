`timescale 1ns/1ps
module tb_core;
    logic clk=0, rst_n=0, link_up=1;
    always #4 clk=~clk;
    logic [11:0] sample=0; logic sample_valid=0;
    logic [31:0] awaddr=0,wdata=0,araddr=0; logic [3:0] wstrb=4'hf;
    logic awvalid=0,wvalid=0,bready=1,arvalid=0,rready=1;
    wire awready,wready,bvalid,arready,rvalid; wire [1:0] bresp,rresp;
    wire [31:0] rdata; wire [127:0] tdata; wire [15:0] tkeep;
    wire tvalid,tlast; logic tready=1; wire [27:0] ftw;
    wire triangle_out,apply_out,busy; integer beats=0,bytes=0,errors=0;

    xadc_xdma_core #(.FIFO_DEPTH(32)) dut (
        .user_clk_i(clk),.user_rst_ni(rst_n),.link_up_i(link_up),
        .sample_clk_i(clk),.sample_rst_ni(rst_n),.xadc_sample_i(sample),
        .xadc_sample_valid_i(sample_valid),.xadc_alarm_i(1'b0),
        .s_axil_awaddr_i(awaddr),.s_axil_awvalid_i(awvalid),.s_axil_awready_o(awready),
        .s_axil_wdata_i(wdata),.s_axil_wstrb_i(wstrb),.s_axil_wvalid_i(wvalid),
        .s_axil_wready_o(wready),.s_axil_bresp_o(bresp),.s_axil_bvalid_o(bvalid),
        .s_axil_bready_i(bready),.s_axil_araddr_i(araddr),.s_axil_arvalid_i(arvalid),
        .s_axil_arready_o(arready),.s_axil_rdata_o(rdata),.s_axil_rresp_o(rresp),
        .s_axil_rvalid_o(rvalid),.s_axil_rready_i(rready),
        .m_axis_c2h_tdata_o(tdata),.m_axis_c2h_tkeep_o(tkeep),
        .m_axis_c2h_tvalid_o(tvalid),.m_axis_c2h_tready_i(tready),
        .m_axis_c2h_tlast_o(tlast),.dds_ftw_o(ftw),.dds_triangle_o(triangle_out),
        .dds_apply_pulse_o(apply_out),.dds_busy_i(1'b0),.stream_busy_o(busy)
    );

    task axil_write(input [31:0] a,input [31:0] d);
        begin
            @(posedge clk); awaddr<=a; wdata<=d; awvalid<=1; wvalid<=1;
            while(!(awready&&wready)) @(posedge clk);
            @(posedge clk); awvalid<=0; wvalid<=0;
            while(!bvalid) @(posedge clk);
        end
    endtask

    function integer keep_count(input [15:0] k);
        integer i; begin keep_count=0; for(i=0;i<16;i=i+1) keep_count=keep_count+k[i]; end
    endfunction
    always @(posedge clk) if(tvalid&&tready) begin
        beats<=beats+1; bytes<=bytes+keep_count(tkeep);
    end

    integer sample_div=0;
    always @(posedge clk) begin
        if(!rst_n) begin sample_div<=0; sample<=0; sample_valid<=0; end
        else begin
            sample_valid<=0;
            if(sample_div==3) begin sample_div<=0; sample<=sample+1; sample_valid<=1; end
            else sample_div<=sample_div+1;
        end
    end

    initial begin
        repeat(6) @(posedge clk); rst_n<=1;
        axil_write(32'h010,32'd20); axil_write(32'h014,32'd0);
        axil_write(32'h008,32'd1);
        wait(tlast&&tvalid&&tready); repeat(2) @(posedge clk);
        if(bytes!=20 || beats!=2) begin
            $display("XADC mismatch bytes=%0d beats=%0d",bytes,beats); errors=errors+1;
        end
        axil_write(32'h008,32'd2); beats=0; bytes=0;
        axil_write(32'h010,32'd64); axil_write(32'h014,32'd1);
        axil_write(32'h008,32'd1);
        wait(tlast&&tvalid&&tready); repeat(2) @(posedge clk);
        if(bytes!=64 || beats!=4) begin
            $display("Stress mismatch bytes=%0d beats=%0d",bytes,beats); errors=errors+1;
        end
        if(errors==0) $display("PASS: XADC and stress paths completed");
        else $fatal(1,"FAIL: %0d errors",errors);
        $finish;
    end
endmodule
