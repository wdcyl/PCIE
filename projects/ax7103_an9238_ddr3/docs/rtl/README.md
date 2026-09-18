# RTL阅读顺序

建议按控制线和数据线交叉阅读：

1. `axil_acquisition_regs.sv`：PC如何配置工程和AD9833。
2. `ad9833_controller.sv`：测试模拟波形如何配置。
3. `acquisition_ddr_core.sv`：所有模块怎样连接。
4. `an9238_capture.sv`：ADC数据怎样形成128-bit数据。
5. `async_fifo.sv`与`fifo_stream_adapter.sv`：数据怎样跨到存储时钟域。
6. `axi_burst_writer.sv`：数据怎样以AXI突发写入缓存区。
7. `axi_test_source.sv`：不接ADC时怎样产生可校验数据。
8. `acquisition_ddr_bd_adapter.sv`：自研RTL怎样接入Vivado Block Design。

各文件的接口、状态机和注意点见同目录对应文档。
