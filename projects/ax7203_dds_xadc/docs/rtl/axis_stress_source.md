# `axis_stress_source.sv`

源码：[rtl/axis_stress_source.sv](../../rtl/axis_stress_source.sv)

## 模块定位

该模块绕过XADC和FIFO，以AXI用户时钟满速生成128 bit测试数据，用于验证XDMA C2H的数据正确性、背压行为和PCIe吞吐率。

## 接口

| 端口 | 方向 | 说明 |
|---|:---:|---|
| `clk_i/rst_ni` | 输入 | 工作时钟和低有效复位 |
| `start_i` | 输入 | 空闲时启动一次传输 |
| `clear_i` | 输入 | 清除当前传输状态 |
| `transfer_bytes_i` | 输入 | 需要产生的总字节数 |
| `pattern_i[1:0]` | 输入 | 数据图案选择 |
| `seed_i[31:0]` | 输入 | 初始值 |
| `m_axis_tdata_o[127:0]` | 输出 | 四个32 bit lane组成的数据 |
| `m_axis_tkeep_o[15:0]` | 输出 | 每个字节的有效标志 |
| `m_axis_tvalid_o` | 输出 | 输出拍有效 |
| `m_axis_tready_i` | 输入 | 下游XDMA可以接收 |
| `m_axis_tlast_o` | 输出 | 本次传输最后一拍 |
| `busy_o` | 输出 | 当前正在产生数据 |
| `done_pulse_o` | 输出 | 最后一拍握手后的单周期完成脉冲 |

## 四种数据图案

| `pattern_i` | 名称 | 一拍中的四个32 bit字 | 下一拍状态 |
|:---:|---|---|---|
| `00` | Ramp | `S,S+1,S+2,S+3` | `S+4` |
| `01` | PRBS | `S,next(S),next²(S),next³(S)` | `next⁴(S)` |
| `10` | Constant | 四个字全部为S | S不变 |
| `11` | Toggle | `S,~S,S,~S` | 下一拍S取反 |

输出拼接为：

```text
TDATA = {lane3, lane2, lane1, lane0}
```

所以主机按小端32 bit数组读取时首先看到 `lane0`。

## PRBS算法

`prbs_next()`执行：

```text
next = {value[30:0], value[31] XOR value[21] XOR value[1] XOR value[0]}
```

如果PRBS模式下软件给出的seed为0，RTL自动换成 `0x1ACEBEEF`，避免全零状态失去变化。

## 传输长度控制

`remaining_q`记录剩余字节数：

- 启动时加载 `transfer_bytes_i`。
- 每次 `TVALID && TREADY` 后通常减16。
- 当剩余不超过16 bytes时，本拍产生 `TLAST=1`。
- 最后一拍握手后清busy并产生done脉冲。

## `TKEEP`和长度约束

模块以32 bit字为最小数据单元，支持4、8、12或16个有效字节：

| 有效字节 | `TKEEP` |
|---:|---:|
| 4 | `0x000F` |
| 8 | `0x00FF` |
| 12 | `0x0FFF` |
| 16 | `0xFFFF` |

软件必须保证压力测试长度是4的倍数。若给出非4字节对齐长度，当前 `TKEEP`逻辑不能精确表达最后1~3 bytes。

## AXI握手保持

`TVALID`直接等于 `busy_o`。当 `TREADY=0` 时，`remaining_q`和 `state_q`均不变化，因此 `TDATA/TKEEP/TLAST`自然保持稳定。

## 启动、清除和重入

- 只有 `start_i && !busy_o`才接受新任务。
- busy期间的start被忽略。
- `transfer_bytes_i=0`时不会进入busy。
- `clear_i`优先于start，直接清remaining和busy，不产生done。

## 主机校验

- Ramp最容易检查连续32 bit递增数据。
- PRBS适合较长时间的数据完整性测试。
- Constant适合检查固定码型和端序。
- Toggle适合观察高翻转率数据下的链路和逻辑行为。
