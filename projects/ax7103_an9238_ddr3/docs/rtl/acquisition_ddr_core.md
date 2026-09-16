# acquisition_ddr_core.sv

业务逻辑顶层。它实例化寄存器、AN9238采集、跨时钟缓存、FIFO流适配、内部测试源和AXI写主机。`MODE[0]`选择ADC或Ramp源；启动条件同时要求PCIe链路、MIG校准和写主机空闲。

正常结束后置`BUFFER_READY`，PC才能读取缓存。溢出或AXI错误时不置就绪，并保留错误状态供软件诊断。
