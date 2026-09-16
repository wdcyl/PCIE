`timescale 1ns/1ps
module tb_rtl;
    logic clk=0,rst_n=0,start=0,clear=0,abort=0;
    always #4 clk=~clk;
    logic [31:0] base=32'h00000ff0,bytes=80;
    wire ready,done,error,s_ready;
    logic [127:0] s_data=0; logic s_valid=0;
    wire [3:0] awid; wire [31:0] awaddr; wire [7:0] awlen; wire [2:0] awsize;
    wire [1:0] awburst; wire awlock; wire [3:0] awcache; wire [2:0] awprot;
    wire [3:0] awqos; wire awvalid; logic awready=1;
    wire [127:0] wdata; wire [15:0] wstrb; wire wlast,wvalid; logic wready=1;
    logic [3:0] bid=0; logic [1:0] bresp=0; logic bvalid=0; wire bready;
    integer errors=0,aw_count=0,w_count=0;

    axi_burst_writer #(.MAX_BURST_BEATS(64)) u_writer(
        .clk_i(clk),.rst_ni(rst_n),.start_i(start),.clear_i(clear),.abort_i(abort),
        .base_addr_i(base),.transfer_bytes_i(bytes),.ready_o(ready),.done_pulse_o(done),.error_o(error),
        .s_data_i(s_data),.s_valid_i(s_valid),.s_ready_o(s_ready),.m_axi_awid_o(awid),
        .m_axi_awaddr_o(awaddr),.m_axi_awlen_o(awlen),.m_axi_awsize_o(awsize),
        .m_axi_awburst_o(awburst),.m_axi_awlock_o(awlock),.m_axi_awcache_o(awcache),
        .m_axi_awprot_o(awprot),.m_axi_awqos_o(awqos),.m_axi_awvalid_o(awvalid),
        .m_axi_awready_i(awready),.m_axi_wdata_o(wdata),.m_axi_wstrb_o(wstrb),
        .m_axi_wlast_o(wlast),.m_axi_wvalid_o(wvalid),.m_axi_wready_i(wready),
        .m_axi_bid_i(bid),.m_axi_bresp_i(bresp),.m_axi_bvalid_i(bvalid),.m_axi_bready_o(bready));

    always @(posedge clk) begin
        if(!rst_n)begin s_data<=0;s_valid<=0;end
        else begin
            s_valid<=1;
            if(s_valid&&s_ready)s_data<=s_data+1;
        end
        if(awvalid&&awready)begin
            if(aw_count==0&&(awaddr!=32'hff0||awlen!=0))begin $display("bad first burst");errors=errors+1;end
            if(aw_count==1&&(awaddr!=32'h1000||awlen!=3))begin $display("bad second burst");errors=errors+1;end
            aw_count<=aw_count+1;
        end
        if(wvalid&&wready)begin
            if(wdata!==w_count)begin $display("bad write data %0d %0h",w_count,wdata);errors=errors+1;end
            w_count<=w_count+1;
            if(wlast)begin bvalid<=1;end
        end
        if(bvalid&&bready)bvalid<=0;
    end

    logic adc_clk=0,adc_rst_n=0,cap_start=0,cap_clear=0;
    always #7 adc_clk=~adc_clk;
    logic [11:0] ch0=0,ch1=12'h100; wire cap_busy,cap_done,cap_overflow;
    wire [31:0] captured; wire fifo_we; wire [127:0] fifo_wdata;
    integer fifo_words=0;
    an9238_capture u_capture(
        .ctrl_clk_i(clk),.ctrl_rst_ni(rst_n),.start_i(cap_start),.clear_i(cap_clear),.sample_pairs_i(8),
        .busy_o(cap_busy),.done_o(cap_done),.overflow_o(cap_overflow),.captured_pairs_o(captured),
        .adc_clk_i(adc_clk),.adc_rst_ni(adc_rst_n),.adc_ch0_i(ch0),.adc_ch1_i(ch1),
        .fifo_wr_en_o(fifo_we),.fifo_wr_data_o(fifo_wdata),.fifo_full_i(1'b0));
    always @(posedge adc_clk)if(adc_rst_n)begin ch0<=ch0+1;ch1<=ch1+1;end
    always @(posedge adc_clk)if(fifo_we)fifo_words<=fifo_words+1;

    initial begin
        repeat(5)@(posedge clk);rst_n<=1;adc_rst_n<=1;
        @(posedge clk);start<=1;cap_start<=1;@(posedge clk);start<=0;cap_start<=0;
        wait(done);repeat(3)@(posedge clk);
        if(error||aw_count!=2||w_count!=5)begin $display("writer failed");errors=errors+1;end
        wait(cap_done);repeat(4)@(posedge clk);
        if(cap_overflow||captured!=8||fifo_words!=2)begin
            $display("capture failed count=%0d words=%0d overflow=%0d",captured,fifo_words,cap_overflow);errors=errors+1;
        end
        base<=0;bytes<=18;@(posedge clk);start<=1;@(posedge clk);start<=0;
        wait(done);if(!error)begin $display("invalid length not rejected");errors=errors+1;end
        if(errors==0)$display("PASS: burst split, capture packing and argument checks");
        else $fatal(1,"FAIL: %0d errors",errors);
        $finish;
    end
endmodule
