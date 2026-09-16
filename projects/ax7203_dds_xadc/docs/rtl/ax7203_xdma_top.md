# `ax7203_xdma_top.sv`

源码：[fpga/rtl/ax7203_xdma_top.sv](../../fpga/rtl/ax7203_xdma_top.sv)

## 模块定位

这是AX7203工程的板级顶层，只负责外部引脚、PCIe参考时钟缓冲和对子系统的例化。它不解析PCIe事务，也不处理采样数据。

## 端口

| 端口 | 方向 | 宽度 | 连接对象 |
|---|:---:|---:|---|
| `pci_exp_rxp/rxn` | 输入 | 4 | 主机发往FPGA的PCIe x4差分接收通道 |
| `pci_exp_txp/txn` | 输出 | 4 | FPGA发往主机的PCIe x4差分发送通道 |
| `sys_clk_p/n` | 输入 | 1+1 | PCIe插槽提供的100 MHz差分参考时钟 |
| `sys_rst_n` | 输入 | 1 | PCIe PERST#，低有效 |
| `xadc_vp/vn` | 输入 | 1+1 | 板载XADC专用差分模拟输入 |
| `dds_sclk` | 输出 | 1 | AD9833串行时钟 |
| `dds_fsync_n` | 输出 | 1 | AD9833低有效帧同步/片选 |
| `dds_sdata` | 输出 | 1 | AD9833串行数据 |
| `led[3:0]` | 输出 | 4 | 链路、传输、DDS和XADC状态调试 |

## 参考时钟设计

顶层例化 `IBUFDS_GTE2`：

```text
sys_clk_p/n
   |
   +-> O      -> sys_clk_gt -> XDMA GTP收发器
   +-> ODIV2  -> sys_clk    -> XDMA逻辑参考时钟
```

`CEB` 固定为0，表示参考时钟缓冲器始终使能。普通逻辑不能直接使用PCIe差分时钟引脚，因此这里必须使用GTE2专用缓冲原语。

## 子系统连接

所有外部端口直接传给 `xdma_subsystem`：

- PCIe串行通道和两个参考时钟进入XDMA。
- `sys_rst_n`复位XDMA和后级业务逻辑。
- `xadc_vp/vn`进入XADC采样器。
- DDS控制信号从子系统输出到J11扩展排针。
- `debug_o`直接连接四个LED。

## 使用和修改注意事项

- 管脚位置不在本文件中定义，而在 `fpga/constraints/ax7203.xdc` 中定义。
- x4表示四组独立高速差分Lane，不是四位普通GPIO。
- 若更换板卡，通常只替换本顶层、约束和PCIe时钟原语连接，业务核心可以保留。
- AX7203用户LED为板级调试用途，需结合原理图确认点亮电平；本模块不反相状态位。
