# `xdma_subsystem.sv`

源码：[fpga/rtl/xdma_subsystem.sv](../../fpga/rtl/xdma_subsystem.sv)

## 模块定位

这是厂商IP和自研RTL之间的集成边界。模块内部例化一个XDMA、一个XADC采样器、一个AD9833控制器和一个业务核心。

```text
PCIe pins -> xdma_0 <-> AXI-Lite/AXI-Stream <-> xadc_xdma_core
                         ^                         ^
                         |                         |
                    host control              XADC samples
                                                   ^
                                                   |
                                             xadc_sampler

axil registers -> DDS setting -> ad9833_controller -> external AD9833
```

## 顶层端口分组

| 分组 | 信号 | 说明 |
|---|---|---|
| XDMA时钟复位 | `sys_clk_i`、`sys_clk_gt_i`、`sys_rst_ni` | PCIe参考时钟及PERST# |
| PCIe物理层 | `pci_exp_rxp_i/rxn_i`、`pci_exp_txp_o/txn_o` | x4高速串行通道 |
| XADC | `xadc_vp_i/vn_i` | 专用模拟差分输入 |
| DDS | `dds_sclk_o`、`dds_fsync_no`、`dds_sdata_o` | AD9833三线写接口 |
| 调试 | `debug_o[3:0]` | 四类关键状态 |

## XDMA侧接口

### AXI-Lite控制通路

`m_axil_*` 是XDMA的PCIe-to-AXI-Lite Master接口。对XDMA而言它是主接口，对 `xadc_xdma_core` 而言是从接口输入。

```text
PC MWr/MRd -> XDMA -> m_axil_* -> axil_control_regs
```

通道包括AW、W、B、AR、R五组标准AXI-Lite信号。`AWPROT/ARPROT`未被业务模块使用，只收集到 `_unused`，防止静态检查报未使用信号。

### C2H数据通路

业务核心生成：

- `c2h_tdata[127:0]`
- `c2h_tkeep[15:0]`
- `c2h_tvalid`
- `c2h_tlast`

XDMA返回 `c2h_tready`。一次有效传输只在 `TVALID && TREADY` 同时为1的时钟沿发生。

### H2C数据通路

IP配置中保留一个H2C通道，但当前项目不使用PC向FPGA批量下发数据：

- XDMA的H2C输出接到内部线网。
- `m_axis_h2c_tready_0`固定为1。
- 收到的数据被直接消费和丢弃。

因此不能把当前H2C理解成已实现的业务功能。

### 中断

XDMA保留一个用户中断接口，但 `usr_irq_req` 固定为0。当前版本采用软件轮询/阻塞读取，没有实现用户MSI事件上报。

## XADC和DDS连接

- `xadc_sampler`使用XDMA输出的 `axi_aclk` 作为DCLK，并输出12 bit样本和有效脉冲。
- `ad9833_controller`也工作在 `axi_aclk` 下，`CLK_DIV=16` 控制串行时钟分频。
- `xadc_xdma_core`输出DDS FTW、波形选择和一次性apply脉冲。

## 时钟与复位

XDMA输出：

| 信号 | 用途 |
|---|---|
| `axi_aclk` | 所有AXI、XADC控制和DDS控制逻辑的工作时钟 |
| `axi_aresetn` | 上述逻辑统一使用的低有效复位 |
| `user_lnk_up` | PCIe链路已进入可工作状态的指示 |

当前采样侧和用户侧都连接 `axi_aclk`。FIFO仍采用双时钟结构，是为了以后接入独立采样时钟的外部ADC。

## 调试位

```text
debug_o[0] = user_lnk_up
debug_o[1] = stream_busy
debug_o[2] = dds_busy
debug_o[3] = xadc_alarm
```

## 使用要求

- Vivado中生成的IP必须命名为 `xdma_0`，并与本文件端口一致。
- 必须启用一个C2H AXI-Stream通道和PCIe-to-AXI-Lite Master。
- 若关闭H2C或用户中断，生成的IP端口会变化，需要同步调整例化。
- 这个模块只连接IP，不自行构造TLP；链路训练、枚举、Completion和DMA描述符均由XDMA处理。
