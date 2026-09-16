# fifo_stream_adapter.sv

异步FIFO是请求后返回`rd_valid`，AXI写主机使用ready/valid。该模块用一个保持寄存器连接两种握手：空闲时发读请求，数据返回后保持`valid_o`，直到下游`ready_i`接收。
