# `xadc_acquisition_controller.sv`

源码：[rtl/xadc_acquisition_controller.sv](../../rtl/xadc_acquisition_controller.sv)

## 模块定位

该模块决定“从连续到来的XADC样本中采多少个、何时写FIFO、是否发生丢样”。它同时处理用户控制时钟域和采样时钟域之间的命令与状态跨域。

## 端口分组

### 用户控制域

| 端口 | 方向 | 说明 |
|---|:---:|---|
| `user_clk_i/user_rst_ni` | 输入 | PC控制和状态读取时钟域 |
| `start_i` | 输入 | 单周期开始脉冲 |
| `clear_i` | 输入 | 单周期清状态脉冲 |
| `sample_count_i` | 输入 | 目标成功采集样本数 |
| `busy_o` | 输出 | 采样域仍在采集 |
| `done_o` | 输出 | 已达到目标样本数，保持到清除或下次开始 |
| `overflow_o` | 输出 | 采样期间曾遇到FIFO满，粘滞状态 |
| `captured_count_o` | 输出 | 成功写FIFO的样本数 |
| `dropped_count_o` | 输出 | FIFO满时未写入的样本次数 |

### 采样域

| 端口 | 方向 | 说明 |
|---|:---:|---|
| `sample_clk_i/sample_rst_ni` | 输入 | XADC样本时钟域 |
| `sample_i[11:0]` | 输入 | XADC原始码 |
| `sample_valid_i` | 输入 | 新样本到达脉冲 |
| `fifo_full_i` | 输入 | FIFO不能再接收数据 |
| `fifo_wr_en_o` | 输出 | FIFO写使能，单周期有效 |
| `fifo_wr_data_o[15:0]` | 输出 | `{4'b0,sample_i}` |

## 开始/清除命令跨域

单周期脉冲不能直接跨时钟域，否则可能完全落在目标时钟两个边沿之间。模块采用toggle事件：

```text
user域收到start -> start_toggle_q翻转
                    |
                    v
sample域两级同步 start_s1/start_s2
                    |
                    v
start_event = start_s2 XOR start_s2_d
```

`clear_i`使用完全相同的结构。两级同步寄存器带 `ASYNC_REG=TRUE` 属性，便于实现工具按同步链处理。

## 目标数量传递

`sample_count_i`经过 `count_s1/count_s2` 两拍采样进入采样域。它不是逐位握手总线，因此必须遵守bundled-data使用约束：软件先稳定写入样本数，再触发start，并且在start被采样前不要修改数量。

## 采集控制行为

该逻辑没有显式枚举状态，`sample_busy_q`相当于IDLE/CAPTURE两状态标志：

```text
IDLE:
  start_event -> 锁存target_q，清计数和异常，进入CAPTURE

CAPTURE:
  sample_valid && !fifo_full -> 写FIFO，captured+1
  sample_valid && fifo_full  -> 不写FIFO，dropped+1，overflow置1
  captured达到target         -> busy清0，done置1，回到IDLE
```

目标数量为0时不进入busy，直接把done置1。

注意：只有成功写入FIFO的样本才计入 `captured_q`。FIFO满时采集不会提前结束，而是继续等待后续可成功写入的样本，直到达到目标数量。

## 计数和状态回传

- `busy/done/overflow`各自经过两级同步回到用户域。
- 32 bit计数先在采样域转成Gray码，再经过两级同步，最后在用户域转回二进制。

Gray码相邻计数只变化一位，降低多位计数器跨域时读到混合值的风险。

## 清除语义

`clear_event`只有在 `sample_busy_q=0` 时生效：

- 清done。
- 清overflow。
- 清captured和dropped。

忙状态下发clear不会中止采集。若需要强制中止，需要扩展一个专门的abort协议，而不是复用clear。

## 饱和与回绕

- `dropped_q`达到 `0xffffffff` 后饱和。
- `captured_q`没有饱和处理，理论上可回绕；正常传输长度受32 bit字节数限制，实际不应超过可表达范围。
