# 硬件接线与上板步骤

## 目标硬件

- ALINX AX7203，默认器件 `XC7A200T-2FBG484`
- AD9833 成品 DDS 模块（带 MCLK 晶振）
- 可插入台式机 PCIe 插槽的板卡；若使用转接线，必须同时满足差分信号完整性、100 MHz REFCLK、PERST# 和供电要求

## AD9833 到 AX7203

数字控制接到 J11：

| AD9833 | AX7203 | FPGA pin |
|---|---|---|
| SCLK | J11-3 | P16 |
| FSYNC/CS | J11-5 | R16 |
| SDATA | J11-7 | N17 |
| VCC | J11-39/40 3.3 V | - |
| GND | J11-1/37/38 | - |

模拟输出接到 XADC J18：

| AD9833 | AX7203 J18 | FPGA pin |
|---|---|---|
| VOUT | VP，pin 1 | L10 |
| GND | VN，pin 2 | M9 |

如果 AD9833 独立供电，仍必须与 AX7203 共地。第一次接入前先用示波器或万用表确认 VOUT 始终处于 XADC 允许输入范围。AX7203 手册给出的 VP/VN 输入幅度为 1 Vpp；不要把负电压、5 V 数字电平或未知偏置直接送入 XADC。必要时增加限流电阻、分压和偏置/钳位电路。

## XDMA 配置要点

- Functional mode: DMA
- Device/Port Type: PCI Express Endpoint
- Link: Gen2 x4
- DMA interface: AXI4-Stream
- AXI data width/frequency: 128 bit / 125 MHz
- Channels: C2H 1，H2C 1（H2C 在本工程中接收后丢弃，仅用于保持常见设备布局）
- PCIe-to-AXI-Lite Master: enable，建议 1 MB aperture
- User interrupt: 1，当前 RTL 未使用
- Vendor/Device ID: `10EE:7024`

不同 Vivado/XDMA 版本的参数名和实例端口可能变化。`create_project.tcl` 会在关键属性不存在时停止；此时按上表在 GUI 中生成名为 `xdma_0` 的 IP，并以生成的 wrapper 为准调整 `xdma_subsystem.sv`，不要静默忽略端口差异。

## 上电顺序

1. 核对 AX7203 板卡版本、供电和拨码；PCIe 调试优先用台式机原生插槽。
2. 烧写 bitstream 后对主机执行冷启动。很多 PC 的 BIOS 只在启动时枚举 PCIe 设备。
3. `lspci -nn -d 10ee:` 检查设备，再检查实际协商速率和宽度。
4. 加载 AMD/Xilinx XDMA PCIe 驱动，确认 user 与 C2H 字符设备。
5. 先运行 Ramp 4 KiB 正确性测试，再增大到 64 MiB 测吞吐；最后接 AD9833 和 XADC。

## 必须核对的板级事项

- `fpga/constraints/ax7203.xdc` 来自 AX7203 手册管脚表，但量产板、核心板和载板修订可能不同，烧写前对照原理图复核。
- XDMA 自动约束与 AX7203 实际 lane 顺序必须一致。若实现阶段出现 GT LOC 冲突，先检查 IP 的 PCIe Block/GT Quad 选择及自动生成 XDC，禁止同时保留互相冲突的 lane 约束。
- 笔记本雷电转 PCIe 可能只协商到 x1，且热插拔/复位行为与台式机不同，不能用它代表 Gen2 x4 性能。
