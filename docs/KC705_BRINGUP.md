# KC705 PCIe 上板说明

## 1. 目标与验证边界

板级工程面向 Xilinx KC705（`xc7k325tffg900-2`），实例化一次 `7 Series Integrated Block for PCI Express`。固定配置如下：

| 项目 | 配置 |
|---|---|
| PCIe 模式 | Endpoint |
| 链路能力 | Gen2 x4 |
| 用户接口 | 64-bit AXI4-Stream，250 MHz |
| 参考时钟 | 100 MHz |
| BAR0 | 4 KiB、32-bit、Non-Prefetchable Memory BAR |
| 中断 | MSI，单向量，支持 64-bit MSI 地址；Legacy INTx关闭 |
| 可选接口 | AER/User Error、Receive Message、Flow-control info、External PIPE关闭 |
| FPGA | XC7K325T-2FFG900 |

本仓库已提供可综合的板级顶层、IP 生成 Tcl、引脚约束和行为仿真。**当前开发环境没有 Vivado，也没有 KC705 和 PCIe 主机，因此未声称完成本地综合、时序收敛、枚举或实板数据传输。** `build_bitstream.tcl` 是可复现入口；首次在目标 Vivado 版本和板卡上使用时，仍须按本文清单完成综合、实现及实板验收。

官方依据：

- [PG054：7 Series Integrated Block for PCI Express](https://docs.amd.com/r/en-US/pg054-7series-pcie/Introduction)
- [PG054：Receive Interface](https://docs.amd.com/r/en-US/pg054-7series-pcie/Receive-Interface)
- [PG054：Transmit Interface](https://docs.amd.com/r/en-US/pg054-7series-pcie/Transmit-Interface)
- [PG054：TLP Format on AXI4-Stream](https://docs.amd.com/r/en-US/pg054-7series-pcie/TLP-Format-on-the-AXI4-Stream-Interface)
- [PG054：MSI Mode](https://docs.amd.com/r/en-US/pg054-7series-pcie/MSI-Mode)
- [UG810：KC705 Evaluation Board User Guide](https://docs.amd.com/v/u/en-US/ug810_KC705_Eval_Bd)

## 2. 硬件与 RTL 边界

`pcie_7x_0` 负责 GT/PHY、LTSSM、Data Link Layer、配置空间、BAR 枚举和 MSI Memory Write 的实际生成。仓库 RTL 负责：

1. 将 IP 的 64-bit RX AXI4-Stream 汇聚为内部 256-bit TLP；
2. 解析命中 BAR0 的 `MRd32/MWr32`，并返回 `Cpl/CplD`；
3. 运行模拟 ADC、异步 FIFO和 C2H `MWr64` 数据通路；
4. 将内部 256-bit TX TLP拆成 64-bit AXI4-Stream；
5. 保存粘滞 IRQ 状态，并通过 `cfg_interrupt/cfg_interrupt_rdy` 请求一次 MSI。

Tcl显式关闭当前应用没有驱动的AER/User Error、Receive Message、Flow-control
information和External PIPE接口，使生成模块的输入边界与板级顶层一致；协议错误
仍由BAR错误计数以及必要的UR Completion反馈给软件。

板级连接为：

```text
PCIe edge connector
  -> pcie_7x_0 (single instance)
  -> 64-bit AXI RX/TX adapter
  -> BAR endpoint + acquisition + FIFO + C2H packetizer
  -> MSI request controller
  -> pcie_7x_0
```

内部 TLP 的 `tdata[31:0]` 为 DW0，AXI 第一拍 `tdata[31:0]` 同样是 DW0，不做额外字节交换。RX `tuser[2]` 表示 BAR0 命中；ECRC、poison、非法 `tkeep` 或超出内部 32-byte 上限的包会被适配层丢弃并计数。TX 使用 store-and-forward，正常包的 `s_axis_tx_tuser` 为零。

IP 输出的 `{cfg_bus_number,cfg_device_number,cfg_function_number}` 作为 Completion 的 Completer ID 和 DMA 的 Requester ID，不能写死。DMA Start 仅在 `user_lnk_up && cfg_command[2]` 时接受，其中 `cfg_command[2]` 是 Bus Master Enable；未使能 BME 时启动会被拒绝并留下状态/中断记录。

## 3. 生成工程与 bitstream

需要安装包含 `xilinx.com:ip:pcie_7x:3.3` 的 Vivado。脚本会检查精确 IP 版本；缺少时直接报错，不会静默换用另一接口版本。

在仓库根目录执行：

```bash
vivado -mode batch -source fpga/kc705/tcl/create_project.tcl
```

工程生成到 `build/vivado/kc705/pcie_kc705.xpr`。完整综合、实现和 bitstream：

```bash
vivado -mode batch -source fpga/kc705/tcl/build_bitstream.tcl
```

成功后 bitstream 复制到 `build/artifacts/kc705/kc705_pcie_top.bit`，并在同目录
生成 timing、DRC 和 utilization 文本报告；若实现后存在负 slack，脚本会报错退出。
可选参数为工程目录和并行任务数：

```bash
vivado -mode batch -source fpga/kc705/tcl/build_bitstream.tcl \
       -tclargs build/vivado/kc705 8
```

脚本每次重新创建工程，`.xci` 和 Vivado 中间文件不提交仓库。项目中应只能看到一个 `pcie_7x_0` IP 和顶层中的一个实例。

## 4. 约束说明

`kc705_pcie.xdc` 只约束：

- PCIe 100 MHz 差分参考时钟：U8/U7；
- Edge Connector `PERST#`：G25；
- 四个用户 LED：AB8、AA8、AC9、AB9。

GTX 通道 LOC、PCIe Hard Block LOC、生成时钟及接口时序由 `pcie_7x_0` 生成的 XDC 负责。不要在板级 XDC 中重复约束 GT lanes。IP 配置指定 KC705、`PCIe_Blk_Locn=X0Y0`，对应的 x4 lane 布局须在 Vivado 的 I/O/Device 视图中与 UG810 原理图再次核对。

四个 LED 为高电平点亮：

| LED | 含义 |
|---|---|
| `led_o[0]` | Link Up |
| `led_o[1]` | Bus Master Enable |
| `led_o[2]` | MSI Enable |
| `led_o[3]` | IRQ Pending 或桥接层错误 |

## 5. MSI 与软件清除流程

MSI 能力和地址/数据寄存器由 PCIe IP 配置空间实现。RTL 在已枚举、链路正常且 `cfg_interrupt_msienable=1` 时保持 `cfg_interrupt=1`，直到 IP 给出 `cfg_interrupt_rdy=1`。该握手只表示 MSI 请求已被 IP 接受，不表示主机已经处理设备事件。

因此驱动中断处理顺序应为：

1. 读取 BAR0 `IRQ_STATUS`，确定 DMA 完成、溢出、协议错误等来源；
2. 完成相应数据/错误处理；
3. 将待清位掩码写入 BAR0 `IRQ_CLEAR`（W1C）；
4. 必要时重新启动下一次采集。

当 MSI 未使能时，RTL 不回退生成 Legacy INTx。64-bit-capable 表示 MSI Capability 允许主机写入高 32-bit 地址；若系统分配的 MSI 地址高位为零，IP 仍可能发送 32-bit Address Memory Write，这属于正常行为。

## 6. 首次上板检查

### 6.1 Vivado

1. 运行 `build_bitstream.tcl`，确认无 critical warning、无未约束端口；
2. 打开 implemented design，检查 PCIe block、GT channel 和参考时钟位置；
3. 检查 `report_timing_summary`，要求所有时钟域 WNS/TNS 通过；
4. 检查 `report_cdc`，特别是采集控制 toggle、Gray 计数器和异步 FIFO；
5. 确认生成 IP 参数确实为 Gen2 x4、64-bit/250 MHz、BAR0 4 KiB、MSI 单向量。

### 6.2 主机枚举

断电插卡，确保 KC705 从稳定配置存储器加载 bitstream 后再让主机释放 PERST#。Linux 下可先查看：

```bash
lspci -nn
lspci -vv -s <BDF>
```

应确认：链路训练成功、协商宽度不超过 x4、BAR0 分配 4 KiB Memory Space、MSI Enable 为 `+`。只有驱动映射了 DMA 缓冲区并写入合法的 64-bit 总线地址后，才能使能采集；不要把普通用户态虚拟地址写入 `DMA_ADDR`。

### 6.3 最小功能顺序

1. 通过 BAR0 读取 ID/VERSION；
2. 读写 Pattern、Sample Count、DMA Address 并回读；
3. 驱动启用 PCI Command 的 Memory Space 和 Bus Master 位；
4. 启用 MSI 和 BAR0 IRQ mask；
5. 启动小批量 Ramp 采集，等待 MSI；
6. 比对 DMA 缓冲区的序列、字节数和包数；
7. 覆盖随机长度、奇数样本、4 KiB 边界和 TX backpressure；
8. 通过 `IRQ_CLEAR` 清除各粘滞事件并确认可再次触发。

## 7. 已知工程限制

- C2H 采用 FPGA 主动发出的 Posted `MWr64`，尚无 Scatter-Gather 描述符环、IOMMU 映射协议或 H2C 读通道；驱动必须提供有效 DMA/bus address。
- BAR 事务当前为单 DW `MRd32/MWr32`；内部包缓存最大 32 byte。
- 板顶层当前以可综合 Pattern Source 代替外部 ADC，引入真实 ADC 时需要新增器件接口、时钟和引脚约束，但 PCIe/BAR/FIFO/DMA 主路径可保持。
- 行为仿真能检查 TLP 适配和 MSI 时序，不能替代 Vivado DRC、时序分析、PCI-SIG 协议检查或实板信号完整性验证。
