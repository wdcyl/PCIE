# `async_fifo.sv`

源码：[rtl/async_fifo.sv](../../rtl/async_fifo.sv)

## 模块定位

这是参数化双时钟FIFO，用于在采样时钟域和XDMA用户时钟域之间传递数据。实现采用本地二进制指针、跨域Gray指针和两级同步器。

## 参数

| 参数 | 默认值 | 限制 | 说明 |
|---|---:|---|---|
| `WIDTH` | 16 | 正整数 | 每个FIFO元素位宽 |
| `DEPTH` | 1024 | 2的整数次幂且至少4 | FIFO深度 |

本工程例化时使用 `WIDTH=16`、`DEPTH=4096`；核心级仿真使用较小深度32。

## 写侧端口

| 端口 | 说明 |
|---|---|
| `wr_clk/wr_rst_n` | 写时钟和低有效复位 |
| `wr_en` | 写请求 |
| `wr_data` | 写数据 |
| `wr_full` | FIFO满，写请求不会改变存储器和指针 |
| `wr_level` | 写域看到的近似占用量 |
| `wr_overflow` | 当拍出现`wr_en && wr_full`的脉冲 |

有效写入条件：

```text
wr_en && !wr_full
```

## 读侧端口

| 端口 | 说明 |
|---|---|
| `rd_clk/rd_rst_n` | 读时钟和低有效复位 |
| `rd_en` | 读请求 |
| `rd_data` | 同步读出的数据 |
| `rd_valid` | 本拍`rd_data`是上一次有效读请求的结果 |
| `rd_empty` | FIFO空 |
| `rd_level` | 读域看到的近似占用量 |
| `rd_underflow` | 当拍出现`rd_en && rd_empty`的脉冲 |

该FIFO不是First-Word-Fall-Through模式。读端先给出 `rd_en`，在后续时钟沿得到 `rd_valid=1` 和有效 `rd_data`。

## 指针结构

地址宽度和指针宽度分别为：

```text
ADDR_WIDTH = log2(DEPTH)
PTR_WIDTH  = ADDR_WIDTH + 1
```

多出来的一位用于区分相同RAM地址对应的不同环次，从而判断满和空。

每侧保留两种指针：

- Binary指针：本地RAM寻址和level计算方便。
- Gray指针：跨时钟域时相邻值只变化一位。

## CDC结构

```text
rd_gray --两级同步--> 写域 -> gray_to_bin -> wr_level/full判断
wr_gray --两级同步--> 读域 -> gray_to_bin -> rd_level/empty判断
```

只有Gray指针跨域，RAM数据通过双口存储方式在各自时钟域访问。

## 空判断

如果下一读指针Gray码等于同步过来的写指针Gray码，则下一状态为空：

```text
rd_empty_next = (rd_gray_next == wr_gray_rd_sync2)
```

## 满判断

写指针即将比同步读指针领先完整一圈时为满。对Gray码表现为最高两位取反、其余位相同：

```text
wr_gray_next == {~rd_gray_sync[top:top-1], rd_gray_sync[remaining]}
```

## level为什么是近似值

`wr_level/rd_level`使用两级同步后的远端指针。远端真实位置可能已经继续前进，所以level是延迟快照，可用于监控或阈值控制，不应作为跨域精确计数依据。

## 综合和复位注意事项

- 读写两侧复位应在各自时钟存在时释放。
- 不要把 `wr_overflow`理解为粘滞错误，它只持续一个写时钟周期；本项目的粘滞overflow由采集控制器维护。
- 修改DEPTH后必须保持2的幂，否则仿真会执行 `$error`。
- 当前XADC方案两侧接同一 `axi_aclk`，模块仍可正常工作；以后接独立ADC采样时钟无需更换接口。
