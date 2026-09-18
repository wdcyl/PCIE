# AX7103 + AN9238 PCIe高速数据采集系统

本工程面向ALINX AX7103（Artix-7 XC7A100T）、AN9238采集模块和外接AD9833信号源。FPGA可配置AD9833产生测试波形，由AN9238完成双路12-bit、65 MSPS采样并写入板载DDR3；主机通过Xilinx XDMA的C2H通道读取采样区，并完成保存、校验、速率统计和波形显示。

> 当前状态：可移植RTL已完成展开与核心级仿真；Vivado建图脚本、AX7103管脚、Linux主机程序和上板步骤已提供。当前机器没有Vivado和目标板，因此尚未生成bitstream，也未声称已经完成实板测试。

## 架构

```text
PC寄存器 -> AD9833 SPI -> 测试模拟波形 -+
                                           v
外部模拟输入 ---------------------------> AN9238 -> 采样/128-bit打包 -> AXI突发写入 -> 板载DDR3
                                                            |
PC软件 <- XDMA C2H <- PCIe Gen2 x4 <- XDMA AXI-MM读取 <------+
   |
   +-- XDMA AXI-Lite -> 控制/状态寄存器

内部Ramp数据源 -> AXI突发写入 -> 板载存储 -> XDMA -> PC
```

MIG负责存储器校准、刷新和物理时序；XDMA负责PCIe链路、枚举、TLP和DMA；自研RTL负责采样控制、数据打包、缓存区地址管理及AXI突发写入。

## 数据格式

每个采样时刻保存为一个32-bit小端字：

```text
[31:28] 0
[27:16] CH1原始12-bit码
[15:12] 0
[11:0]  CH0原始12-bit码
```

四个采样对组成一个128-bit AXI数据拍。采集字节数和缓冲区基地址必须16字节对齐。

## 目录

```text
rtl/              采集、寄存器、测试源、跨时钟缓存和AXI写主机
fpga/ip/          AX7103官方MIG配置
fpga/rtl/         Vivado Block Design模块适配层
fpga/constraints/ AX7103与AN9238管脚约束
fpga/tcl/         工程重建和bitstream脚本
sim/              不依赖厂商IP的核心仿真
software/         Linux XDMA采集与波形查看程序
docs/             架构、寄存器、构建、验证和逐文件说明
```

## 快速验证

```bash
python scripts/run_simulation.py
vivado -mode batch -source fpga/tcl/create_project.tcl
vivado -mode batch -source fpga/tcl/build_bitstream.tcl
make -C software
sudo software/pcie_capture --mode ramp --bytes 67108864 --out ramp.bin
sudo software/pcie_capture --mode adc --freq 100000 --mclk 25000000 --bytes 1048576 --out adc.bin
python software/plot_capture.py adc.bin --count 4096
```

详细步骤见[设计说明](docs/DESIGN.md)、[AD9833与AN9238链路](docs/AD9833_AN9238_PATH.md)、[Vivado与IP配置](docs/VIVADO_BUILD.md)、[上板流程](docs/HARDWARE_BRINGUP.md)、[寄存器表](docs/REGISTER_MAP.md)和[验证记录](docs/VERIFICATION.md)。

## 参数边界

- AN9238：12 bit、最高65 MSPS；两路按16 bit容器保存，数据需求约260 MB/s。
- PCIe：Gen2 x4，链路编码后的方向带宽上限约2 GB/s，实际还受TLP、DMA、主机和驱动影响。
- XDMA用户接口：128 bit、125 MHz，接口理论上限2 GB/s，不等于实测吞吐率。
- 默认采集区：基地址`0x00000000`，默认长度1 MiB；必须落在MIG映射范围内。

## 参考来源

板卡管脚和MIG参数依据用户提供的ALINX AX7103官方资料包中的`PCIE_test`与`ad9238_ethernet`案例。工程未复制其业务RTL；采集与AXI控制逻辑为本仓库重新实现。`ax7103_mig.prj`是MIG生成器配置文件，修改存储器型号或板卡版本时应重新运行MIG GUI。
