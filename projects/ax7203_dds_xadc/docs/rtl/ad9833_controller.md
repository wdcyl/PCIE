# `ad9833_controller.sv`

源码：[rtl/ad9833_controller.sv](../../rtl/ad9833_controller.sv)

## 模块定位

该模块把PC写入寄存器的28 bit频率控制字和波形选择转换成AD9833所需的三线串行写序列。接口为写方向，不读取AD9833状态。

## 端口与参数

| 名称 | 方向 | 说明 |
|---|:---:|---|
| `CLK_DIV` | 参数 | 串行半周期包含的输入时钟周期数，默认16 |
| `clk_i/rst_ni` | 输入 | 控制时钟和低有效复位 |
| `apply_i` | 输入 | 空闲时启动一次完整配置 |
| `ftw_i[27:0]` | 输入 | Frequency Tuning Word |
| `triangle_i` | 输入 | 0输出正弦，1输出三角波 |
| `busy_o` | 输出 | 正在发送五个配置字 |
| `done_pulse_o` | 输出 | 配置结束的单周期脉冲 |
| `sclk_o` | 输出 | AD9833 SCLK |
| `fsync_no` | 输出 | AD9833低有效FSYNC/片选 |
| `sdata_o` | 输出 | AD9833 SDATA，MSB first |

串行时钟频率近似为：

```text
f_SCLK = f_clk / (2 * CLK_DIV)
```

默认 `axi_aclk=125 MHz`、`CLK_DIV=16`时约为3.90625 MHz。

## 五个16 bit配置字

`make_word()`根据 `word_q`产生：

| 序号 | 配置字 | 含义 |
|---:|---|---|
| 0 | `0x2100` | B28=1并置RESET，允许连续写28 bit频率字 |
| 1 | `{2'b01, FTW[13:0]}` | FREQ0低14位 |
| 2 | `{2'b01, FTW[27:14]}` | FREQ0高14位 |
| 3 | `0xC000` | PHASE0=0 |
| 4 | `0x2000`或`0x2002` | 退出RESET，选择正弦或三角波 |

软件按下式计算FTW：

```text
FTW = round(f_out * 2^28 / f_MCLK)
```

这里的MCLK是AD9833模块自身晶振频率，不是FPGA的 `axi_aclk`。

## 状态机

| 状态 | 行为 | 下一状态 |
|---|---|---|
| `IDLE` | FSYNC=1、SCLK=1；收到apply后锁存FTW/波形并准备字0 | `FALL` |
| `FALL` | 拉低SCLK，AD9833在下降沿采样当前SDATA | `RISE` |
| `RISE` | 拉高SCLK；若还有位则移位并准备下一bit | `FALL`或`GAP` |
| `GAP` | FSYNC保持高形成字间隔；装载下一个配置字 | `FALL`或`DONE` |
| `DONE` | 清busy并产生done脉冲 | `IDLE` |

每个字从bit15发送到bit0。`shift_q`保存当前字，`bit_q`记录正在发送的位置，`word_q`记录五个字中的序号。

## 启动语义

- `apply_i`只在 `IDLE` 被检查。
- 启动时立即锁存 `ftw_i` 和 `triangle_i`，发送过程中外部寄存器变化不会影响当前序列。
- busy期间再次产生apply会被忽略；软件应先读取STATUS中的DDS busy位。

## 复位输出

复位时：

```text
busy=0
done=0
SCLK=1
FSYNC_N=1
SDATA=0
```

这使AD9833串行接口保持非选中状态，但不会保证外部AD9833已经被硬件复位；需要软件在链路建立后执行一次apply。

## 使用限制

- 本模块只支持FREQ0和PHASE0，不支持FREQ1、PHASE1、扫频或运行时快速切换。
- 不读取外设返回值，因此“done”只表示FPGA已经完成串行发送，不等于模拟输出已经被测量验证。
- AD9833模块供电和逻辑电平必须匹配AX7203 3.3 V IO。
