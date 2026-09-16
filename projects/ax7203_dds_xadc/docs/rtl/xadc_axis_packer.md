# `xadc_axis_packer.sv`

源码：[rtl/xadc_axis_packer.sv](../../rtl/xadc_axis_packer.sv)

## 模块定位

该模块从16 bit FIFO读取XADC样本，每8个样本打包成一拍128 bit AXI4-Stream，并生成末拍 `TKEEP` 和 `TLAST`。

## 接口

| 分组 | 信号 | 说明 |
|---|---|---|
| 控制 | `start_i`、`clear_i`、`sample_count_i` | 启动、清除和目标样本数 |
| FIFO | `fifo_data_i`、`fifo_valid_i`、`fifo_empty_i`、`fifo_rd_en_o` | 同步读FIFO接口 |
| AXIS | `m_axis_tdata_o`、`tkeep_o`、`tvalid_o`、`tready_i`、`tlast_o` | 送往XDMA的128 bit流 |
| 状态 | `busy_o`、`done_pulse_o` | 正在发送和单周期完成脉冲 |

## 内部寄存器

| 寄存器 | 作用 |
|---|---|
| `remaining_q` | 还需要从FIFO接收的样本数 |
| `buffer_q[127:0]` | 当前正在拼装的AXI数据拍 |
| `sample_in_beat_q` | 当前拍已经写到第几个16 bit槽位 |
| `read_pending_q` | 已向同步FIFO发出读请求，等待`fifo_valid` |

## FIFO读取协议

FIFO是同步读，不是组合输出，因此需要两步：

```text
1. !fifo_empty && !read_pending -> fifo_rd_en=1，read_pending=1
2. fifo_valid && read_pending   -> 消费fifo_data，read_pending=0
```

这样不会重复读取，也不会把尚未有效的 `fifo_data_i` 当成样本。

## 数据排列

第N个样本写入：

```text
buffer[N*16 +: 16]
```

因此一拍128 bit中：

```text
bits[15:0]    = sample0
bits[31:16]   = sample1
...
bits[127:112] = sample7
```

在小端主机按16 bit读取时，样本顺序保持为sample0、sample1……。

## 何时输出一拍

满足任一条件时，把 `buffer_with_new`送到AXI输出：

- 当前加入的是第8个样本，即 `sample_in_beat_q==7`。
- 当前加入的是整个传输的最后一个样本，即 `remaining_q==1`。

后一种情况会同时置 `TLAST=1`。

## `TKEEP`生成

每个样本占2 bytes，低字节开始连续有效：

| 本拍样本数 | `TKEEP` |
|---:|---:|
| 1 | `0x0003` |
| 2 | `0x000F` |
| 3 | `0x003F` |
| 4 | `0x00FF` |
| 5 | `0x03FF` |
| 6 | `0x0FFF` |
| 7 | `0x3FFF` |
| 8 | `0xFFFF` |

## AXI背压

当 `TVALID=1` 且 `TREADY=0` 时：

- 输出数据、TKEEP和TLAST保持不变。
- 不再读取FIFO。
- `busy_o`保持为1。

只有 `TVALID && TREADY` 后才能撤销当前有效拍并继续组装下一拍。

## 启动和完成

- `start_i && !busy_o`锁存样本数量并开始工作。
- `sample_count_i=0`时不会进入busy。
- 最后一拍被XDMA真正接收后，`busy_o`清0，`done_pulse_o`持续一个时钟。
- `clear_i`立即清除内部发送状态；正常使用时应确保没有未完成DMA描述符后再清除。
