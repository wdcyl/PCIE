# AX7203 XADC + PCIe XDMA 数据采集系统

本工程面向 ALINX AX7203（Artix-7 XC7A200T）实现一个可上板扩展的 PCIe Endpoint 数据采集链路。外部 AD9833 小板产生测试波形，板载 XADC 完成 12 bit 采样，FPGA 将样本缓存、打包为 AXI4-Stream，再通过 Xilinx XDMA 的 C2H 通道送入 Linux 主机内存。另有独立的内部 Ramp/PRBS 压力源，用于把“模拟采集速度”和“PCIe DMA 通路能力”分开验证。

> 当前状态：RTL、Vivado 重建脚本、AX7203 约束、Linux 测试程序和验证步骤已整理；尚未在目标板卡上生成 bitstream 或实测。因此文档中的带宽数字是接口上限/测试目标，不是实测成绩。

## 总体架构

```text
AD9833 VOUT -> AX7203 J18 VP/VN -> XADC -> acquisition controller
                                               |
                                               v
                                          sample FIFO
                                               |
                                               v
PC software <- XDMA C2H <- 128-bit AXI4-Stream packer
     |
     +-> BAR / XDMA AXI-Lite -> control/status registers
                                  |
                                  +-> AD9833 SPI controller

Internal Ramp/PRBS source ---------------------> XDMA C2H
```

XDMA 负责 PCIe 链路训练、枚举所需配置空间、TLP/DMA 搬运和 AXI 接口转换；自研 RTL 只处理控制寄存器、采样、缓存、打包、测试数据和 AD9833 配置，不重复实现 PCIe 协议栈。

## 两种数据模式

- `XADC`：每个样本以小端 16 bit 保存，低 12 bit 为 XADC 原始码，高 4 bit 为 0。
- `Ramp/PRBS`：内部发生器每拍产生 128 bit，用于验证 C2H 数据正确性与 DMA 吞吐率，不代表模拟采集速率。

## 目录

```text
rtl/                  可复用 SystemVerilog 业务逻辑
fpga/rtl/             XDMA 边界封装与 AX7203 顶层
fpga/constraints/     AX7203 管脚约束
fpga/tcl/             Vivado 工程重建/bitstream 脚本
sim/                  不依赖 XDMA 的核心级 testbench
scripts/              仿真启动脚本
software/             Linux XDMA 测试程序
docs/                  设计、寄存器、接线与验证说明
```

## 快速使用

1. 安装带 XDMA IP 的 Vivado，执行：

   ```bash
   vivado -mode batch -source fpga/tcl/create_project.tcl
   ```

2. 打开生成工程，核对器件、XDMA 版本、GT lane 顺序和本板修订版原理图，再综合实现。直接构建可执行：

   ```bash
   vivado -mode batch -source fpga/tcl/build_bitstream.tcl
   ```

3. Linux 主机加载 AMD/Xilinx `dma_ip_drivers` 中的 XDMA 驱动，确认 `/dev/xdma0_user` 与 `/dev/xdma0_c2h_0` 存在。

4. 编译并运行主机程序：

   ```bash
   make -C software
   sudo software/pcie_capture --mode ramp --bytes 67108864 --out ramp.bin
   sudo software/pcie_capture --mode xadc --bytes 1048576 --freq 10000 --out xadc.bin
   ```

详细信息见 [设计说明](docs/DESIGN.md)、[硬件接线与上板](docs/HARDWARE_BRINGUP.md) 和 [验证计划](docs/VERIFICATION.md)。

## 复用来源

工程复用了本仓库前一版 Endpoint 采集设计中的异步 FIFO、AXI-Stream 压力源及 XDMA 接口组织方式；ADC 前端、控制寄存器、单通道样本打包、AD9833 控制、AX7203 顶层和主机程序按本方案重新组织。

## 参考资料

- ALINX, `AX7203 User Manual`（板卡 PCIe、J11、J18 和管脚定义）
- AMD, `PG195 DMA/Bridge Subsystem for PCI Express`
- AMD, `UG480 7 Series FPGAs and Zynq-7000 SoC XADC Dual 12-Bit 1 MSPS`
- Analog Devices, `AD9833 Data Sheet`
