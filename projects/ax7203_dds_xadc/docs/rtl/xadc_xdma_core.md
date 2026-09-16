# `xadc_xdma_core.sv`

源码：[rtl/xadc_xdma_core.sv](../../rtl/xadc_xdma_core.sv)

## 模块定位

这是与板卡和厂商IP相对独立的业务顶层，负责把控制寄存器、XADC采集、FIFO、数据打包和压力测试源组合起来。

## 子模块

| 实例 | 模块 | 作用 |
|---|---|---|
| `u_regs` | `axil_control_regs` | 接收PC控制并提供状态寄存器 |
| `u_capture` | `xadc_acquisition_controller` | 执行定长样本采集 |
| `u_sample_fifo` | `async_fifo` | 缓存16 bit样本 |
| `u_xadc_stream` | `xadc_axis_packer` | 16 bit样本转128 bit AXI-Stream |
| `u_stress` | `axis_stress_source` | 产生内部测试数据 |

## 接口分组

| 分组 | 主要信号 | 说明 |
|---|---|---|
| 用户时钟 | `user_clk_i/user_rst_ni` | AXI-Lite、AXI-Stream和统计逻辑 |
| 采样时钟 | `sample_clk_i/sample_rst_ni` | XADC样本写入侧 |
| 采样输入 | `xadc_sample_i`、`xadc_sample_valid_i`、`xadc_alarm_i` | 12 bit样本、有效和告警 |
| AXI-Lite | `s_axil_*` | XDMA转来的PC BAR控制访问 |
| C2H AXIS | `m_axis_c2h_*` | 送入XDMA的128 bit数据流 |
| DDS控制 | `dds_ftw_o`、`dds_triangle_o`、`dds_apply_pulse_o`、`dds_busy_i` | AD9833配置 |

## 模式选择

`mode[0]`直接控制数据源选择：

| `mode[0]` | 数据源 | 启动对象 |
|:---:|---|---|
| 0 | XADC采集通路 | `xadc_acquisition_controller`和`xadc_axis_packer` |
| 1 | 内部压力源 | `axis_stress_source` |

MUX最终选择 `TDATA/TKEEP/TVALID/TLAST`，两个源只有被选中的源才能看到有效的 `TREADY`。

模式在一次传输开始前由软件设置。传输忙时不得修改 `MODE`，否则组合MUX可能在包中途切换数据源。

## 采样数量换算

XADC样本固定保存为16 bit，因此：

```text
sample_count = transfer_bytes / 2
```

RTL通过 `transfer_bytes[31:1]`实现整数除2。软件必须保证XADC模式字节数为2的倍数。

## 状态寄存器拼接

模块生成32 bit `status`：

| 位 | 信号 | 含义 |
|---:|---|---|
| 0 | `link_up_i` | PCIe链路已建立 |
| 1 | `stream_busy_o` | 当前数据流正在发送 |
| 2 | `capture_done` | 本轮XADC采集达到目标数量 |
| 3 | `capture_overflow` | 采样时遇到FIFO满 |
| 4 | `fifo_empty` | FIFO空 |
| 5 | `fifo_full` | FIFO满 |
| 6 | `dds_busy_i` | AD9833控制器忙 |
| 7 | `xadc_alarm_i` | XADC告警或过温 |
| 8 | `select_stress` | 当前为压力测试模式 |
| 31:9 | 0 | 保留 |

## 字节与背压统计

`count_keep()`计算每个被XDMA接收的AXI拍中 `TKEEP` 的1数量：

```text
TVALID && TREADY -> stream_bytes_q += popcount(TKEEP)
TVALID && !TREADY -> backpressure_q += 1
```

`clear_pulse`同时清零两个统计值。背压计数到 `0xffffffff` 后饱和，不回绕。

## 一次XADC传输流程

```text
1. PC设置TRANSFER_BYTES和MODE=0
2. PC写CONTROL.start
3. start_pulse同时启动采集控制器和数据打包器
4. 采集控制器把有效XADC样本写入FIFO
5. 打包器从FIFO读取并组成128 bit数据
6. XDMA通过TREADY接收
7. 最后一个样本产生TLAST
8. stream_busy清零，计数寄存器保留结果
```

## 边界与限制

- 当前没有把模式锁存在启动时刻，软件必须在busy期间保持配置稳定。
- `clear_pulse`清统计和两个数据源的活动状态，但FIFO本身依靠复位清指针；正常使用应在上一轮数据完全读完后再开始下一轮。
- `capture_busy`用于内部观察，目前对外状态的busy来自数据打包器或压力源。
