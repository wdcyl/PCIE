# AXI-Lite控制与状态寄存器

本文件集中说明PC通过XDMA BAR窗口访问的全部寄存器。寄存器宽度均为32 bit，地址按4字节对齐。

## 属性说明

| 属性 | 含义 |
|---|---|
| RO | 只读，软件写入无效 |
| RW | 可读写，写入值保持到下一次写入或复位 |
| WO | 只写命令位，读取返回0 |
| W1P | 写1产生一个控制时钟周期的脉冲，硬件不会保存该1 |
| Sticky | 事件发生后保持为1，直到指定的清除条件出现 |
| Reserved | 保留位，读取为0，软件写入时应写0 |

AXI-Lite写入支持`WSTRB[3:0]`字节选通。`CONTROL`和`DDS_CONTROL`只有最低字节有效；访问未定义地址或非对齐地址返回`SLVERR`。

## 寄存器总表

| 偏移 | 名称 | 属性 | 复位值 | 主要用途 |
|---:|---|---|---:|---|
| `0x000` | ID | RO | `0x41443932` | 识别本设计 |
| `0x004` | VERSION | RO | `0x00030000` | RTL接口版本 |
| `0x008` | CONTROL | WO/W1P | `0x00000000` | 启动采集、清除状态 |
| `0x00C` | STATUS | RO | 动态 | 链路、采集、写入和DDS状态 |
| `0x010` | CAPTURE_BYTES | RW | `0x00100000` | 单次采集字节数，默认1 MiB |
| `0x014` | BUFFER_BASE | RW | `0x00000000` | DDR3目标缓冲区基地址 |
| `0x018` | MODE | RW | `0x00000000` | AN9238或内部Ramp数据源选择 |
| `0x01C` | TEST_SEED | RW | `0x00000000` | Ramp数据初始值 |
| `0x020` | CAPTURED_PAIRS | RO | `0x00000000` | 已采集/生成的32-bit字数 |
| `0x024` | WRITTEN_LO | RO | `0x00000000` | 已写DDR3字节数低32位 |
| `0x028` | WRITTEN_HI | RO | `0x00000000` | 已写DDR3字节数高32位 |
| `0x02C` | DDS_FTW | RW | `0x0A3D70A` | AD9833的28-bit频率调谐字 |
| `0x030` | DDS_CONTROL | RW/W1P | `0x00000000` | AD9833波形选择和配置触发 |

## `0x000` ID

固定值为`0x41443932`，ASCII可写作`AD92`。软件应先读取本寄存器，确认BAR映射到了正确设备。

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `[31:0]` | DESIGN_ID | RO | 固定`0x41443932` |

## `0x004` VERSION

当前接口版本为`3.0.0`。版本变化时，PC软件可以据此判断寄存器布局是否兼容。

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `[31:16]` | MAJOR | RO | 主版本号，当前为`3` |
| `[15:8]` | MINOR | RO | 次版本号，当前为`0` |
| `[7:0]` | PATCH | RO | 修订号，当前为`0` |

## `0x008` CONTROL

该寄存器的有效位均为单周期命令脉冲，不会保持。`START`和`CLEAR`不要在同一次写操作中同时置1。

| Bit | 名称 | 属性 | 写入1的作用 |
|---:|---|---|---|
| `0` | START | W1P | 请求开始一次采集/测试；仅在PCIe链路建立、MIG校准完成且AXI写主机空闲时被接受 |
| `1` | CLEAR | W1P | 清除采集状态、错误、完成标志、缓冲区就绪标志和字节计数，同时清除`DDS_DONE` |
| `[31:2]` | RESERVED | WO | 保留，写0 |

推荐写法：

```c
regs[CONTROL/4] = 1u << 1;  /* CLEAR */
regs[CONTROL/4] = 1u << 0;  /* START */
```

## `0x00C` STATUS

| Bit | 名称 | 属性 | 为1时的含义 | 清除条件 |
|---:|---|---|---|---|
| `0` | LINK_UP | RO | XDMA报告PCIe链路已经建立 | 随硬件链路状态变化 |
| `1` | CALIB_DONE | RO | MIG完成DDR3初始化和校准 | 随MIG状态变化 |
| `2` | CAPTURE_BUSY | RO | AN9238采集模块正在接收样本；Ramp模式下通常为0 | AN9238达到设定采样数或被清除 |
| `3` | WRITER_READY | RO | AXI写主机空闲，可以接受新的`START` | AXI写主机启动后自动变0 |
| `4` | CAPTURE_DONE | RO/Sticky | 最近一次DDR3写入已经结束 | 新的有效`START`或`CONTROL.CLEAR` |
| `5` | OVERFLOW | RO/Sticky | AN9238数据到达时FIFO已满，本次数据不再连续 | `CONTROL.CLEAR`或新一轮采集初始化 |
| `6` | AXI_ERROR | RO/Sticky | 参数非法、AXI写响应非OKAY或写流程发生错误 | `CONTROL.CLEAR`或下一次写主机初始化 |
| `7` | BUFFER_READY | RO/Sticky | DDR3缓冲区包含一块完整、未报告错误的数据，可以启动C2H读取 | 新的有效`START`或`CONTROL.CLEAR` |
| `8` | TEST_MODE | RO | 当前选择内部Ramp数据源，是`MODE.SELECT_TEST`的镜像 | 写`MODE` |
| `9` | DDS_BUSY | RO | AD9833控制器正在发送5个16-bit配置字 | 配置序列完成后自动清0 |
| `10` | DDS_DONE | RO/Sticky | 最近一次AD9833配置序列已经完成 | 新的`DDS_APPLY`或`CONTROL.CLEAR` |
| `[31:11]` | RESERVED | RO | 保留，读取为0 | - |

开始采集前至少应满足：

```text
LINK_UP=1 && CALIB_DONE=1 && WRITER_READY=1
```

采集完成判据是`BUFFER_READY=1`，不能只看`CAPTURE_BUSY=0`。`CAPTURE_BUSY=0`只说明ADC采样阶段结束，不代表数据已经全部写入DDR3。

## `0x010` CAPTURE_BYTES

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `[31:0]` | BYTE_COUNT | RW | 单次采集或Ramp测试需要写入DDR3的总字节数 |

约束：

- 必须非0。
- 必须为16的整数倍，因为内部AXI数据宽度为128 bit。
- AN9238模式下每个采样时刻占4字节，因此采样对数量为`CAPTURE_BYTES / 4`。
- 地址范围不能超过MIG实际映射的DDR3空间。

## `0x014` BUFFER_BASE

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `[31:0]` | BASE_ADDRESS | RW | 本次写入DDR3的AXI起始地址，也是PC执行C2H `pread`时使用的设备侧偏移 |

地址必须16字节对齐，并且`BUFFER_BASE + CAPTURE_BYTES`必须落在MIG可访问范围内。`axi_burst_writer`会自动在4 KiB边界拆分AXI突发，但不会替软件检查整个DDR3容量。

## `0x018` MODE

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `0` | SELECT_TEST | RW | `0`：使用AN9238采集数据；`1`：使用内部Ramp测试数据 |
| `[31:1]` | RESERVED | RW | 保留，软件写0 |

更改`MODE`只改变下一次启动选择的数据源，不会自动触发采集。

## `0x01C` TEST_SEED

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `[31:0]` | SEED | RW | 内部Ramp模式的第一个32-bit测试值，之后每个32-bit字依次加1 |

本寄存器在AN9238模式下不会影响采样数据。

## `0x020` CAPTURED_PAIRS

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `[31:0]` | WORD_COUNT | RO | AN9238模式：已接收的双通道采样对数；Ramp模式：已写入的32-bit测试字数 |

AN9238的一个采样对由同一时刻的CH0和CH1组成，占一个32-bit字。该计数用于观察进度，不应代替`BUFFER_READY`完成判据。

## `0x024` WRITTEN_LO与`0x028` WRITTEN_HI

两个寄存器组成64-bit已写字节计数：

```text
BYTES_WRITTEN = (WRITTEN_HI << 32) | WRITTEN_LO
```

| 寄存器 | Bit | 名称 | 属性 | 含义 |
|---|---:|---|---|---|
| WRITTEN_LO | `[31:0]` | BYTE_COUNT_LO | RO | 已完成AXI W通道握手的字节数低32位 |
| WRITTEN_HI | `[31:0]` | BYTE_COUNT_HI | RO | 已完成AXI W通道握手的字节数高32位 |

计数在新的有效`START`或`CONTROL.CLEAR`时清零，每完成一个128-bit数据拍的`WVALID && WREADY`握手增加16。

## `0x02C` DDS_FTW

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `[27:0]` | FTW | RW | 写入AD9833两个频率寄存器字的28-bit频率调谐字 |
| `[31:28]` | RESERVED | RO | 读取为0，写入时忽略 |

计算公式：

```text
FTW = round(f_out × 2^28 / MCLK)
f_out = FTW × MCLK / 2^28
```

复位值`0x0A3D70A`在`MCLK=25 MHz`时约对应`1 MHz`。实际计算必须使用AD9833模块真实的MCLK频率。

## `0x030` DDS_CONTROL

| Bit | 名称 | 属性 | 含义 |
|---:|---|---|---|
| `0` | TRIANGLE | RW | `0`：正弦波；`1`：三角波 |
| `1` | APPLY | W1P | 写1后锁存`DDS_FTW`和`TRIANGLE`，开始发送AD9833配置序列 |
| `[31:2]` | RESERVED | RO | 保留，读取为0，写入忽略 |

`APPLY`读取始终为0。若在`DDS_BUSY=1`期间再次写`APPLY=1`，当前实现会忽略新的触发，因此软件应先等待`DDS_BUSY=0`。

## 推荐的软件操作顺序

### 内部Ramp通路测试

1. 读取`ID`和`VERSION`。
2. 写`CONTROL.CLEAR=1`。
3. 写`MODE.SELECT_TEST=1`、`TEST_SEED`、`BUFFER_BASE`和`CAPTURE_BYTES`。
4. 等待`LINK_UP=1`、`CALIB_DONE=1`、`WRITER_READY=1`。
5. 写`CONTROL.START=1`。
6. 轮询`BUFFER_READY`；若`OVERFLOW`或`AXI_ERROR`置位则停止。
7. 使用XDMA C2H从`BUFFER_BASE`读取`CAPTURE_BYTES`，逐32-bit字校验递增数据。

### AD9833与AN9238采集

1. 读取`ID`和`VERSION`，写`CONTROL.CLEAR=1`。
2. 根据输出频率和MCLK计算FTW，写`DDS_FTW`。
3. 写`DDS_CONTROL.TRIANGLE`，同时将`DDS_CONTROL.APPLY`写1。
4. 等待`DDS_BUSY=0`且`DDS_DONE=1`。
5. 写`MODE.SELECT_TEST=0`、`BUFFER_BASE`和`CAPTURE_BYTES`。
6. 确认`LINK_UP=1`、`CALIB_DONE=1`、`WRITER_READY=1`后写`CONTROL.START=1`。
7. 等待`BUFFER_READY=1`，再由XDMA C2H读取DDR3缓冲区。

## 一个最小配置示例

```c
/* 偏移除以4后作为mmap得到的uint32_t数组下标 */
regs[0x008/4] = 1u << 1;       /* CLEAR */
regs[0x02c/4] = ftw;           /* DDS_FTW */
regs[0x030/4] = 1u << 1;       /* SINE + APPLY */
while (regs[0x00c/4] & (1u << 9)) { /* wait DDS_BUSY */ }

regs[0x018/4] = 0;             /* AN9238 mode */
regs[0x014/4] = 0;             /* DDR3 base */
regs[0x010/4] = 1024 * 1024;   /* 1 MiB */
regs[0x008/4] = 1u << 0;       /* START */
while (!(regs[0x00c/4] & (1u << 7))) { /* wait BUFFER_READY */ }
```
