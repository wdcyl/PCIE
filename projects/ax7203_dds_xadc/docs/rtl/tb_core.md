# `tb_core.sv`

源码：[sim/tb_core.sv](../../sim/tb_core.sv)

## 文件定位

这是 `xadc_xdma_core` 的自检查testbench，不参与综合。它不例化XDMA、PCIe PHY或真实XADC，只验证自研业务核心的基本控制和数据打包。

## 时钟和复位

```text
clk每4 ns翻转一次 -> 周期8 ns -> 125 MHz
rst_n初始为0，等待6个上升沿后释放
link_up固定为1
TREADY固定为1
```

用户时钟域和采样时钟域在此testbench中使用同一个 `clk`。

## XADC样本模型

testbench每4个用户时钟产生一个 `sample_valid`，并让12 bit样本值递增：

```text
sample=0,1,2,3...
```

它只模拟“数字样本已经从XADC出来”的接口，不模拟模拟电压、量化误差或XADC DRP行为。

## AXI-Lite写任务

`axil_write(address,data)`执行：

1. 在时钟上升沿驱动AW地址、W数据并拉高两个VALID。
2. 等待 `AWREADY && WREADY`。
3. 撤销VALID。
4. 等待 `BVALID`写响应。

该任务用于设置传输长度、模式和CONTROL启动位。当前testbench没有实现AXI-Lite读任务。

## AXI-Stream监控

每次 `TVALID && TREADY`：

- `beats`加1。
- `bytes`增加 `TKEEP` 中1的数量。

`keep_count()`完成16 bit `TKEEP`的popcount。

## 用例1：XADC模式

```text
TRANSFER_BYTES = 20
MODE = 0
CONTROL.start = 1
```

20 bytes对应10个16 bit样本。期望：

- 输出2个AXI beat。
- 第一拍16 bytes，第二拍4 bytes。
- 最后一拍产生TLAST。
- 总有效字节数为20。

## 用例2：Ramp压力模式

首先写 `CONTROL.clear`，然后：

```text
TRANSFER_BYTES = 64
MODE = 1
CONTROL.start = 1
```

期望输出4个完整128 bit beat，总计64 bytes。

## 通过条件

两个用例都满足期望时输出：

```text
PASS: XADC and stress paths completed
```

否则执行 `$fatal`。运行入口是：

```bash
python scripts/run_simulation.py
```

## 未覆盖内容

- PCIe链路训练与枚举。
- XDMA内部描述符和TLP行为。
- AXI随机背压。
- AXI-Lite读和AW/W分离到达的随机时序。
- FIFO满、丢样和跨异步时钟压力。
- AD9833串行波形。
- XADC硬核模拟。

这些属于后续可扩展的验证项，当前PASS不能等同于上板通过。
