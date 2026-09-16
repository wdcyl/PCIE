# SystemVerilog 模块文档索引

本目录遵循“一份 `.sv` 源码对应一份 Markdown 说明”的规则。建议按下列顺序阅读。

## 综合设计文件

| 层次 | 源码 | 文档 | 主要作用 |
|---|---|---|---|
| 板级 | `fpga/rtl/ax7203_xdma_top.sv` | [ax7203_xdma_top](ax7203_xdma_top.md) | AX7203管脚、PCIe参考时钟和系统顶层 |
| 集成 | `fpga/rtl/xdma_subsystem.sv` | [xdma_subsystem](xdma_subsystem.md) | XDMA、XADC、DDS和业务核心集成 |
| 核心 | `rtl/xadc_xdma_core.sv` | [xadc_xdma_core](xadc_xdma_core.md) | 控制面、采集面和压力测试数据源汇总 |
| 控制 | `rtl/axil_control_regs.sv` | [axil_control_regs](axil_control_regs.md) | AXI-Lite寄存器和主机控制接口 |
| 模拟输入 | `rtl/xadc_sampler.sv` | [xadc_sampler](xadc_sampler.md) | 7 Series XADC硬核封装 |
| 采集控制 | `rtl/xadc_acquisition_controller.sv` | [xadc_acquisition_controller](xadc_acquisition_controller.md) | 定长采集、CDC命令和统计 |
| 缓存 | `rtl/async_fifo.sv` | [async_fifo](async_fifo.md) | Gray指针双时钟FIFO |
| 数据打包 | `rtl/xadc_axis_packer.sv` | [xadc_axis_packer](xadc_axis_packer.md) | 8个16 bit样本打包为128 bit AXI-Stream |
| 压力源 | `rtl/axis_stress_source.sv` | [axis_stress_source](axis_stress_source.md) | Ramp/PRBS/常量/翻转测试数据 |
| DDS控制 | `rtl/ad9833_controller.sv` | [ad9833_controller](ad9833_controller.md) | AD9833三线串行配置状态机 |

## 仿真文件

| 源码 | 文档 | 主要作用 |
|---|---|---|
| `sim/tb_core.sv` | [tb_core](tb_core.md) | 业务核心级自动检查 |
| `sim/vendor_stubs.sv` | [vendor_stubs](vendor_stubs.md) | 无Vivado环境下的厂商原语/IP端口桩 |

## 整体调用关系

```text
ax7203_xdma_top
└── xdma_subsystem
    ├── xdma_0                         厂商IP
    ├── xadc_sampler
    │   └── XADC                       7 Series硬核
    ├── ad9833_controller
    └── xadc_xdma_core
        ├── axil_control_regs
        ├── xadc_acquisition_controller
        ├── async_fifo
        ├── xadc_axis_packer
        └── axis_stress_source
```

## 两条数据流

```text
采集模式：VP/VN -> XADC -> 采集控制 -> FIFO -> 16转128打包 -> XDMA C2H
压力模式：Ramp/PRBS/Constant/Toggle -> 128 bit AXI-Stream -> XDMA C2H
```

控制流始终为：

```text
PC BAR访问 -> XDMA PCIe-to-AXI-Lite Master -> axil_control_regs -> 各业务模块
```
