# PCIe FPGA Data Acquisition Engine

[![RTL Regression](https://github.com/wdcyl/PCIE/actions/workflows/ci.yml/badge.svg)](https://github.com/wdcyl/PCIE/actions/workflows/ci.yml)

面向 FPGA 开发学习与工程展示的 PCIe 高速数据采集内核。项目从事务层出发，实现 BAR0 控制、MRd/MWr/CplD、双时钟采集、异步 FIFO、C2H DMA TLP、事件中断和端到端自检。

## 主要功能

- 256-bit 单拍 TLP 内部接口，支持 `valid/ready` 背压。
- BAR0 单 DW `MRd32`、`MWr32`，读请求返回 `CplD`。
- Completion 正确返回 Requester ID、Tag、Byte Count、Lower Address和Completer ID。
- 未映射或不支持的 Memory Read 返回 `UR Cpl`；非法 `MWr32/MWr64` 只计错、不返回 Completion。
- 16-bit ADC数据源：Ramp、PRBS16、常量、三角波。
- Toggle CDC命令跨时钟域与Gray计数器状态回传。
- 参数化 Gray Pointer 异步 FIFO。
- C2H DMA：生成 `MWr64`，每包最多8个16-bit样本。
- 自动处理尾部奇数样本Byte Enable和4 KiB边界拆包。
- Completion/DMA发送仲裁、粘滞中断、W1C中断清除。
- 自动回归覆盖随机背压、数据一致性、非法访问、边界拆包、溢出和恢复。

## 系统结构

```mermaid
flowchart LR
    HOST[Host / Root Complex] -->|MRd32 / MWr32| EP[PCIe TLP Endpoint]
    EP --> BAR[BAR0 Registers]
    BAR --> CTRL[Acquisition Controller]
    ADC[ADC Pattern Source] --> CTRL
    CTRL --> AFIFO[Asynchronous FIFO]
    AFIFO --> DMA[C2H DMA Packetizer]
    DMA -->|MWr64| HOST
    EP --> ARB[TX Arbiter]
    DMA --> ARB
    ARB --> HOST
```

工程内部使用规范化的 TLP 格式。仓库同时提供 KC705 板级顶层，将 Xilinx 7-Series PCIe Hard IP 的 64-bit AXI4-Stream 接口转换为该内部格式。详细边界见 [设计说明](docs/DESIGN.md)，工程生成和上板步骤见 [KC705 上板说明](docs/KC705_BRINGUP.md)。

## 快速运行

依赖：

- Python 3
- Icarus Verilog 11或更新版本

运行：

```bash
python scripts/run_sim.py
```

生成 KC705 Vivado 工程或 bitstream：

```bash
make vivado-project
make bitstream
```

板级目标为 XC7K325T、PCIe Gen2 x4、64-bit/250 MHz、BAR0 4 KiB 和单向量 MSI。本地尚未完成 Vivado 和实板验证，使用前请执行 [KC705 上板检查](docs/KC705_BRINGUP.md)。

成功时输出：

```text
=== Regression summary ===
checks=28 errors=0 cpl=7 dma_packets=17 dma_bytes=250
ALL TESTS PASSED
PASS: 174 Xilinx 7-Series bridge/MSI checks
PASS: all simulations and KC705 top-level elaboration completed
```

波形生成在 `build/pcie_acq.vcd`。

## 目录

```text
PCIE/
├── rtl/
│   ├── pcie_tlp_endpoint.sv    # BAR请求解析及Completion生成
│   ├── bar_registers.sv        # BAR0控制与状态寄存器
│   ├── adc_pattern_source.sv   # 可综合ADC替代数据源
│   ├── acquisition_controller.sv
│   ├── async_fifo.sv           # Gray指针双时钟FIFO
│   ├── c2h_dma_engine.sv       # MWr64 C2H DMA打包
│   ├── tlp_tx_arbiter.sv       # Completion/DMA发送仲裁
│   ├── xilinx_7x_axis_bridge_64.sv
│   ├── xilinx_7x_msi_controller.sv
│   └── pcie_acq_top.sv         # 可移植应用顶层
├── fpga/kc705/
│   ├── rtl/kc705_pcie_top.sv   # 单个PCIe IP的板级顶层
│   ├── constraints/kc705_pcie.xdc
│   └── tcl/                    # Vivado工程和bitstream脚本
├── sim/
│   ├── tb_pcie_acq.sv          # Root Complex与Host Memory行为模型
│   ├── tb_xilinx_7x_integration.sv
│   └── pcie_7x_0_stub.sv       # 仅用于CI端口展开，不含协议模型
├── scripts/
│   └── run_sim.py
├── docs/
│   ├── DESIGN.md
│   ├── KC705_BRINGUP.md
│   ├── REGISTER_MAP.md
│   └── VERIFICATION.md
└── .github/workflows/ci.yml
```

## 当前工程边界

本仓库实现 PCIe事务层学习内核与采集数据通路，并提供生成 KC705 所需加密厂商 Hard IP 的 Tcl；GT收发器、LTSSM、Data Link Layer和配置空间由 Vivado IP生成。当前限制：

- BAR只支持单DW MRd32/MWr32。
- DMA只实现C2H Posted MWr64，不包含H2C、描述符环和多队列。
- 内部TLP一次完整放入256-bit单拍，Payload最大4DW。
- KC705 工程尚未在本地 Vivado 或实板验证；生成 bitstream 后仍需完成时序、DRC、枚举和 DMA 压力测试。

这些边界均在文档中显式说明，便于后续继续扩展，而不会把厂商PHY能力误写成自研RTL能力。

## 文档

- [详细设计与IP说明](docs/DESIGN.md)
- [KC705 Vivado工程与上板说明](docs/KC705_BRINGUP.md)
- [BAR0寄存器表](docs/REGISTER_MAP.md)
- [验证方案与测试结果](docs/VERIFICATION.md)

## License

MIT

## AX7203 XADC + XDMA 扩展工程

新增的板级采集方案位于 [projects/ax7203_dds_xadc](projects/ax7203_dds_xadc/README.md)：面向 ALINX AX7203，采用板载 XADC、AD9833 测试信号源和 Xilinx XDMA，实现真实采样 C2H 与内部压力测试两条数据路径。

## AX7103 + AN9238 + XDMA扩展工程

[projects/ax7103_an9238_ddr3](projects/ax7103_an9238_ddr3/README.md)面向ALINX AX7103和AN9238采集模块，采用MIG管理板载存储、XDMA AXI Memory Mapped通路完成C2H读取。工程包含AN9238采集、AXI突发写、内部Ramp校验源、Vivado自动建图脚本、Linux采集程序以及逐文件设计文档。

当前已完成可移植RTL展开与核心仿真；Vivado综合、bitstream和实板性能数据仍需在目标环境完成。
