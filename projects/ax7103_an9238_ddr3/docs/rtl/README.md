# RTL阅读顺序

建议按控制线和数据线交叉阅读：

1. `axil_acquisition_regs.sv`：PC如何配置工程。
2. `acquisition_ddr_core.sv`：所有模块怎样连接。
3. `an9238_capture.sv`：ADC数据怎样形成128-bit数据。
4. `async_fifo.sv`与`fifo_stream_adapter.sv`：数据怎样跨到存储时钟域。
5. `axi_burst_writer.sv`：数据怎样以AXI突发写入缓存区。
6. `axi_test_source.sv`：不接ADC时怎样产生可校验数据。
7. `acquisition_ddr_bd_adapter.sv`：自研RTL怎样接入Vivado Block Design。

各文件的接口、状态机和注意点见同目录对应文档。
