# 当前测试结果

## 已运行

在本机使用 Icarus Verilog 编译并运行 `scripts/run_simulation.py`：

```text
PASS: XADC and stress paths completed
```

覆盖内容：

- 10 个 XADC 样本打包为 20 bytes，末拍 `TKEEP/TLAST` 正确
- 64 bytes Ramp 压力数据形成 4 个完整的 128 bit beat
- AXI-Lite 对模式、长度与启动寄存器的基本写访问

Icarus 对部分 `always_comb` 常量选择给出兼容性提示，不是仿真错误。

## 未运行

- Vivado synthesis / implementation / bitstream
- XDMA IP wrapper 联编
- PCIe 枚举、BAR 实机读写和 DMA 实测
- AD9833 到 XADC 模拟链路

未运行项目不能作为上板通过或性能成绩引用。完成实机验证后，应把命令输出、Vivado 报告与数据文件补到本页。
