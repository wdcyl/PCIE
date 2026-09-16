# `axil_control_regs.sv`

源码：[rtl/axil_control_regs.sv](../../rtl/axil_control_regs.sv)

## 模块定位

该模块是32 bit AXI4-Lite从设备。PC对XDMA user BAR的访问被XDMA转换为AXI-Lite主事务，本模块完成地址译码、寄存器读写和应答。

## 完整寄存器表

| 偏移 | 名称 | 权限 | 复位值 | 内容和使用方法 |
|---:|---|:---:|---:|---|
| `0x000` | `ID` | RO | `0x58414430` | 固定ASCII标识`XAD0`，用于确认BAR映射正确 |
| `0x004` | `VERSION` | RO | `0x00010000` | RTL接口版本1.0 |
| `0x008` | `CONTROL` | WO | 0 | bit0写1产生一次`start_pulse`；bit1写1产生一次`clear_pulse` |
| `0x00C` | `STATUS` | RO | 外部输入 | 由`xadc_xdma_core`拼接的实时状态 |
| `0x010` | `TRANSFER_BYTES` | RW | 4096 | 本轮C2H传输字节数 |
| `0x014` | `MODE` | RW | 0 | bit0选择压力源；bits[2:1]选择压力图案 |
| `0x018` | `STRESS_SEED` | RW | 0 | Ramp/PRBS/常量/翻转模式的初始32 bit值 |
| `0x01C` | `DDS_FTW` | RW | 0 | bits[27:0]为AD9833频率控制字，bits[31:28]读为0 |
| `0x020` | `DDS_CONTROL` | RW/脉冲 | 0 | bit0保存三角波选择；bit1写1产生一次`dds_apply_pulse` |
| `0x024` | 保留 | - | - | 未映射，访问返回SLVERR |
| `0x028` | `STREAM_BYTES_LO` | RO | 外部输入 | 已被XDMA接受的字节计数低32位 |
| `0x02C` | `STREAM_BYTES_HI` | RO | 外部输入 | 已被XDMA接受的字节计数高32位 |
| `0x030` | `CAPTURED` | RO | 外部输入 | 成功写入FIFO的XADC样本数 |
| `0x034` | `DROPPED` | RO | 外部输入 | 因FIFO满而未写入的样本数 |
| `0x038` | `BACKPRESSURE` | RO | 外部输入 | AXI `TVALID=1,TREADY=0`累计周期数 |

RO表示只读，WO表示写入产生动作但不保存对应数据，RW表示可读写。向只读地址写入虽然总线返回OKAY，但case中没有赋值，因此寄存器不会改变；未映射地址返回SLVERR。

## `MODE`位定义

| 位 | 名称 | 含义 |
|---:|---|---|
| 0 | `SOURCE` | 0=XADC，1=压力测试源 |
| 2:1 | `PATTERN` | 00=Ramp，01=PRBS，10=Constant，11=Toggle |
| 31:3 | 保留 | 当前RTL忽略 |

所以常用值为：

```text
MODE=0x0：XADC
MODE=0x1：Stress Ramp
MODE=0x3：Stress PRBS
MODE=0x5：Stress Constant
MODE=0x7：Stress Toggle
```

## `CONTROL`为什么是脉冲

`start_pulse_o`和`clear_pulse_o`每个时钟默认自动清0，只有对应写事务提交时置1。因此软件无需先写1再写0：

```text
write CONTROL = 0x1 -> start脉冲持续一个clk
write CONTROL = 0x2 -> clear脉冲持续一个clk
```

`DDS_CONTROL.bit1`采用同样机制，而bit0会保存到 `dds_triangle_o`。

## AXI-Lite写控制

AXI-Lite写地址AW和写数据W是两个独立通道，可能同拍到达，也可能前后到达。模块用：

- `aw_pending_q/awaddr_q`保存先到的写地址。
- `w_pending_q/wdata_q/wstrb_q`保存先到的写数据和字节使能。
- 地址和数据都齐全且当前没有未完成B响应时，`write_commit=1`。

提交后：

1. 根据低12位地址译码。
2. 更新目标寄存器或产生动作脉冲。
3. `BVALID`置1。
4. 已映射地址返回`BRESP=OKAY(00)`，未映射返回`SLVERR(10)`。
5. 等待主设备给出`BREADY`后撤销`BVALID`。

这种设计不要求AW和W同时出现。

## 写字节使能

`merge_wstrb()`按 `WSTRB[3:0]`逐字节合并新旧数据：

```text
WSTRB[0] -> bits[7:0]
WSTRB[1] -> bits[15:8]
WSTRB[2] -> bits[23:16]
WSTRB[3] -> bits[31:24]
```

`CONTROL`和`DDS_CONTROL`动作位只在 `WSTRB[0]=1` 时有效。

## AXI-Lite读控制

当 `ARVALID && ARREADY`：

1. 锁存地址对应的读值到`RDATA`。
2. 已映射地址返回`RRESP=OKAY`，否则返回`SLVERR`且数据为0。
3. `RVALID`保持为1，直到主设备给出`RREADY`。

在`RVALID=1`期间，`ARREADY=0`，因此模块同一时间最多保留一个未完成读响应。

## 软件建议顺序

```text
1. 读取ID和VERSION
2. 写CONTROL.clear
3. 写TRANSFER_BYTES
4. 写MODE和STRESS_SEED，必要时配置DDS
5. PC提交C2H读请求
6. 写CONTROL.start
7. 读取STATUS和统计寄存器
```

传输busy期间不建议改变长度、模式或种子。
