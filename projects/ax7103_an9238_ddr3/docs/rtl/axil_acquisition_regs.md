# axil_acquisition_regs.sv

实现32-bit AXI-Lite从接口，AW与W允许独立到达并分别锁存；两者齐备后执行一次写操作并返回BRESP。读通道一次保持一个RVALID，直到主机接收。

配置项包括采集长度、缓存地址、ADC/测试模式和测试种子；状态项包括链路、校准、忙、完成、溢出、AXI错误及计数。完整表见`../REGISTER_MAP.md`。
