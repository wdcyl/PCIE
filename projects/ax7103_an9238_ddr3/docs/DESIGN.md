# 设计说明

## 数据通路

AN9238的两个12-bit CMOS输出在65 MHz采样时钟域进入`an9238_capture`。同一时刻的CH0/CH1组成32-bit采样对，每四组组成一个128-bit字，经跨时钟缓存送往存储控制时钟域。`axi_burst_writer`按最多64拍的INCR突发写入指定地址，并在4 KiB边界主动拆分事务。

采集完成后，状态寄存器置位`BUFFER_READY`。Linux程序使用XDMA C2H设备对同一AXI地址执行`pread`，XDMA发起AXI读请求，经互连和MIG读出采样数据，再通过PCIe搬入主机内存。


## 信号源与采集前端

PC可通过新增DDS寄存器写入28-bit频率调谐字并触发`ad9833_controller`。控制器从AX7103的J11输出SCLK、FSYNC和SDATA；AD9833模拟输出接入AN9238的SMA输入。AN9238仍经J13向FPGA提供两路12-bit并行采样数据，因此加入信号源不会改变后端FIFO、DDR3或XDMA数据通路。

## 控制通路

PC对`/dev/xdma0_user`映射的BAR窗口读写。XDMA把访问转换成AXI-Lite，经过时钟转换后进入`axil_acquisition_regs`。软件依次写采集长度、缓存基地址、模式与种子，最后写`CONTROL.START`。

## 厂商IP分工

| IP | 配置 | 作用 |
|---|---|---|
| XDMA | Endpoint、Gen2 x4、AXI-MM、128 bit/125 MHz、1个H2C和1个C2H | PCIe链路、枚举、TLP及主机DMA |
| MIG 7 Series | AX7103板载32-bit DDR3、AXI接口、官方管脚配置 | 初始化校准、刷新、PHY和存储访问 |
| AXI Interconnect | 2个Slave入口、1个Master出口 | 仲裁XDMA与采集写主机对MIG的访问 |
| AXI Clock Converter | 内存和控制各1个 | XDMA时钟域与MIG UI时钟域转换 |
| Clocking Wizard | 200 MHz板钟、65 MHz采样钟 | 板载时钟缓冲及AN9238采样时钟生成 |
| Processor System Reset | MIG UI时钟域 | 产生同步复位，等待时钟与校准稳定 |

## 缓冲策略

当前实现为单缓冲：一次采集写入`BUFFER_BASE`开始的连续区域，写完后由PC读取。它适合定长采集和功能验证。连续无缝采集可扩展成A/B双缓冲：FPGA写A时PC读B，块完成后交换所有权；进一步可增加环形描述符和中断。

## 异常处理

- 长度或基地址未按16字节对齐：写主机拒绝启动并置错误。
- 数据来不及写入：采集立即终止并置`OVERFLOW`，不把不连续数据伪装成有效记录。
- AXI BRESP非OKAY：置`AXI_ERROR`，不置`BUFFER_READY`。
- PCIe链路或MIG校准未完成：忽略启动命令。
