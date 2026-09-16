# `vendor_stubs.sv`

源码：[sim/vendor_stubs.sv](../../sim/vendor_stubs.sv)

## 文件定位

该文件为无Vivado/Icarus环境下的语法和顶层展开检查提供三个厂商模块的端口桩：

- `IBUFDS_GTE2`
- `XADC`
- `xdma_0`

它只用于仿真编译，禁止加入Vivado综合sources，否则会与真实UNISIM原语和生成的XDMA IP重名冲突。

## `IBUFDS_GTE2`桩

行为被极度简化为：

```text
O = I
ODIV2 = 0
```

它的作用只是让 `ax7203_xdma_top` 能被Icarus展开，不模拟差分输入、GT参考时钟质量或真实除2输出。

## `XADC`桩

桩保留了源码使用到的初始化参数和端口，但所有输出固定为0：

```text
DO=0, DRDY=0, EOC=0, CHANNEL=0, BUSY=0, ALM=0
```

因此它不能生成样本，也不能验证XADC初始化参数。核心级testbench选择直接驱动 `xadc_xdma_core` 的样本接口，而不是依赖这个桩。

## `xdma_0`桩

桩声明了工程需要的：

- PCIe串行端口。
- `sys_clk/sys_clk_gt/sys_rst_n`。
- AXI4-Stream C2H/H2C。
- AXI-Lite Master。
- 用户中断和MSI状态。

简化行为：

- `axi_aclk=sys_clk`。
- `axi_aresetn=sys_rst_n`。
- `user_lnk_up=1`。
- C2H `TREADY=1`。
- AXI-Lite不主动发起事务。
- H2C不产生数据。
- PCIe TX固定为0。

## 能验证什么

使用该文件进行顶层elaboration可以发现：

- 模块名或端口名拼写错误。
- 端口宽度不匹配。
- 顶层内部缺少连接。
- 普通SystemVerilog语法错误。

## 不能验证什么

- XDMA生成版本的真实端口是否完全一致。
- PCIe链路、GT约束、枚举、BAR和DMA。
- AXI协议时序和XDMA背压。
- 时钟频率、相位、抖动和复位时序。
- XADC转换或AD9833模拟输出。

Vivado工程必须使用 `create_project.tcl`生成的真实IP重新综合实现，不能以stub展开通过代替Vivado验证。
