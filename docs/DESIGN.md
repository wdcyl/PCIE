# PCIe FPGA数据采集引擎设计说明

## 1. 设计目标

工程围绕 FPGA开发岗位常见的三个问题展开：

1. 主机如何通过BAR读写FPGA控制寄存器；
2. 不同时钟域的采样数据如何可靠进入PCIe数据通路；
3. FPGA如何把采集数据封装成Memory Write TLP并写入主机内存。

顶层不绑定具体FPGA型号。PCIe物理层和数据链路层由器件Hard IP负责；本工程聚焦Hard IP用户侧之后的事务处理、采集、CDC、缓存和DMA打包。

## 2. 总体架构

```text
                       PCIe RX TLP
                           |
                  +--------v---------+
                  | pcie_tlp_endpoint|
                  | MRd/MWr parser   |
                  | Cpl/CplD builder |
                  +----+--------+----+
                       | BAR    | Completion
                 +-----v----+   |
                 | BAR0 regs|   |
                 +-----+----+   |
                       |        v
 ADC clock domain      |   +----------------+
 +-------------+  +----v-->| TX TLP arbiter |----> PCIe TX TLP
 | ADC patterns|->| capture| +-------^--------+
 +-------------+  +----+---+         |
                       |             |
                 +-----v------+  +---+-------------+
                 | async FIFO |->| C2H DMA MWr64   |
                 +------------+  +-----------------+
```

控制路径与数据路径分离：

- 控制路径：Host `MRd/MWr -> Endpoint -> BAR0 -> control/status`。
- 数据路径：`ADC -> Acquisition -> Async FIFO -> DMA MWr64 -> Host Memory`。

## 3. IP核与自研模块边界

### 3.1 当前仓库实际包含的模块

| 模块 | 类型 | 作用 |
|---|---|---|
| `pcie_tlp_endpoint` | 自研RTL | 解析BAR0 MRd32/MWr32，生成Cpl/CplD |
| `bar_registers` | 自研RTL | 配置、状态、IRQ、统计寄存器 |
| `adc_pattern_source` | 自研RTL | Ramp/PRBS/常量/三角波采样源 |
| `acquisition_controller` | 自研RTL | 固定长度采集、CDC、丢样统计 |
| `async_fifo` | 自研RTL | Gray Pointer双时钟FIFO |
| `c2h_dma_engine` | 自研RTL | 16-bit样本打包为MWr64 TLP |
| `tlp_tx_arbiter` | 自研RTL | Completion优先的双源发送仲裁 |
| `pcie_acq_top` | 自研RTL | 系统集成与状态/中断汇总 |

当前可移植内核没有实例化厂商黑盒IP。这不是遗漏，而是因为PCIe Hard IP端口、Descriptor格式、时钟复位和约束都依赖具体FPGA系列与板卡。

### 3.2 接入Xilinx器件时选择的IP

如果保留本工程自研TLP与DMA：

- 7 Series：`7 Series Integrated Block for PCI Express`；
- UltraScale/UltraScale+：`UltraScale Devices Gen3 Integrated Block for PCI Express`；
- 增加Wrapper，将厂商`CQ/CC/RQ/RC`或旧式RX/TX Stream转换成本工程的Canonical TLP。

如果目标是更快完成板级数据搬运：

- 可选`DMA/Bridge Subsystem for PCI Express (XDMA)`；
- XDMA已经实现PCIe Requester、Completion管理和Scatter-Gather DMA；
- 这时应保留ADC、Acquisition和Async FIFO，将自研TLP Endpoint/DMA替换为XDMA的AXI-Lite与AXI-Stream接口。

两条路线不能混写：Integrated Block路线展示TLP处理能力；XDMA路线展示系统集成和AXI数据通路能力。

### 3.3 可选替换IP

- `async_fifo`可以替换为Xilinx `XPM_FIFO_ASYNC`或FIFO Generator。
- 板级调试可以加入ILA监视TLP握手、FIFO水位和DMA状态。
- 当前仓库继续保留自研FIFO，便于展示Gray码指针和CDC设计。

## 4. 内部TLP接口

接口宽度为256 bit，每个TLP限制为单拍：

```text
tdata[31:0]    = DW0
tdata[63:32]   = DW1
tdata[95:64]   = DW2
tdata[127:96]  = DW3或第一个Payload DW
tdata[255:128] = 后续Payload
```

`tkeep[31:0]`每位对应一个有效字节。`tvalid`有效且`tready`无效时，发送方必须保持`tdata/tkeep/tlast`不变。

实际Hard IP的DWORD排列和Descriptor格式可能不同，因此板级Wrapper必须根据对应Product Guide转换，不能直接按位连接。

## 5. M1：BAR与Completion

### 5.1 支持的请求

- 3DW、Length=1的MRd32；
- 3DW、Length=1并携带一个Payload DW的MWr32；
- 必须命中BAR0；
- First DW Byte Enable不能为0；
- 单DW请求的Last DW Byte Enable必须为0。

### 5.2 MRd流程

```text
RX接受MRd
  -> 解析Requester ID、Tag、Address、FBE
  -> BAR组合读
  -> 计算有效Byte Count与Lower Address
  -> 生成3DW Header + 1DW Data的CplD
  -> TX valid/ready发送
```

CplD会回传原请求的Requester ID和Tag，使Requester能够匹配Outstanding Read。

### 5.3 异常处理

- 未定义BAR地址、格式错误的Memory Read或不支持的MRd64：返回`UR Cpl`并增加错误计数。
- 非法MWr32/MWr64属于Posted Request：不返回Completion，仅增加错误计数。
- 其它包类型只计错，不盲目生成Completion，避免对Posted包或Completion包错误回应。
- Endpoint内部有一项Completion缓冲，可在发送背压期间保持报文稳定。

## 6. M2：ADC、采集控制和异步FIFO

### 6.1 ADC替代数据源

`adc_pattern_source`是可综合的数据源，便于不依赖外部ADC调试数据路径：

| `PATTERN[1:0]` | 模式 |
|---:|---|
| 0 | 16-bit递增Ramp |
| 1 | PRBS16 |
| 2 | 常量，数值来自`PATTERN[31:16]` |
| 3 | 三角波 |

后续接实际ADC时，只需用ADC接口模块替换该数据源，保持`sample_data/sample_valid`接口不变。

### 6.2 命令和状态CDC

PCIe域的Start/Clear是单周期脉冲。脉冲先转换为Toggle，再经过两级同步器进入ADC域，通过异或检测事件，避免慢时钟漏采单周期脉冲。当前版本未实现运行中的跨时钟域Abort/FIFO Flush，因此CONTROL bit1/2保留；Clear Stats应在空闲时使用。

`sample_count`和`pattern`属于Bundled Data CDC：软件先写配置，再等待至少两个ADC时钟后发Start；采集期间必须保持配置稳定。`pattern`在ADC域经过两级寄存器后进入数据源。

`captured_count`和`dropped_count`在ADC域转成Gray码，经两级同步后在PCIe域还原，避免多bit二进制计数同时翻转造成撕裂。

### 6.3 异步FIFO

FIFO在两侧维护二进制指针，在跨时钟域时只同步Gray指针：

```text
binary pointer -> Gray pointer -> 2FF synchronizer -> Gray-to-binary
```

Full判断采用“下一写指针与同步读指针相差一整圈”的Gray码比较；Empty判断为下一读指针等于同步写指针。`wr_level/rd_level`是保守监测值，不用于精确跨域计费。

FIFO满时采集控制器不写入，设置Sticky Overflow并增加Dropped Count；成功写入数量达到目标后才置Done。

## 7. M3：C2H DMA

### 7.1 DMA状态机

```text
IDLE --Start--> FILL --收满本包--> SEND --Handshake--> FILL/IDLE
```

- `FILL`：逐个请求同步FIFO数据，最多保留一个未完成FIFO读。
- 每包最多8个16-bit样本，即4DW Payload。
- `SEND`：形成单拍MWr64；背压期间全部字段保持不变。
- 最后一包发送后置位Sticky Done与IRQ。

### 7.2 MWr64布局

```text
DW0: Fmt=011, Type=00000, Length=1..4DW
DW1: Requester ID, Tag=0, Last BE, First BE
DW2: Host Address[63:32]
DW3: Host Address[31:2], 00
DW4..DW7: ADC Sample Payload
```

两个16-bit样本组成一个Payload DW。样本数为奇数时，最后一个DW只有低2字节有效：

- 单DW Payload：`FBE=0011, LBE=0000`；
- 多DW Payload：最后一DW使用`LBE=0011`。

请求不会跨越4 KiB边界。若当前地址距离边界不足以容纳8个样本，DMA会缩短本包，在下一地址重新发包。

当前打包器要求主机目的地址4-byte对齐；软件必须在Start前保证`DMA_ADDR[1:0]=0`。选择板卡和驱动后，可把未对齐检查升级为硬件配置错误状态。

### 7.3 统计与中断

- `packets_sent`：Clear Stats以来已交给TX子系统的MWr64数量；
- `bytes_sent`：Clear Stats以来按照有效16-bit样本累计；
- IRQ bit0：DMA完成；
- IRQ bit1：采集溢出；
- IRQ bit2：TLP协议或BAR访问错误。

IRQ状态是Sticky并采用Write-One-to-Clear；只有`IRQ_STATUS & IRQ_ENABLE`非零时才拉高顶层`irq_o`。

## 8. TX仲裁

Completion优先于DMA：

```text
Priority 1: Cpl/CplD
Priority 2: DMA MWr64
```

仲裁器包含一拍Holding Register。当下游不Ready时保持选中的TLP，避免组合优先级在背压期间改变输出报文。

## 9. 时钟与复位

| 时钟域 | 模块 |
|---|---|
| `pcie_clk` | Endpoint、BAR、DMA、TX Arbiter、Host侧FIFO读口 |
| `adc_clk` | ADC Source、Acquisition、FIFO写口 |

顶层输入`pcie_rst_ni/adc_rst_ni`均为低有效。除DMA状态机使用PCIe域同步高有效内部复位外，其余时序模块采用异步拉低；板级设计应在各时钟域同步释放复位。PCIe Hard IP的`user_reset`应作为PCIe域复位来源。

## 10. 板级集成步骤

选定开发板后需要新增：

1. PCIe Hard IP配置，包括Link Width、Generation、BAR0大小和Class Code；
2. 差分参考时钟、PERST#、GT Lane和ADC引脚约束；
3. Hard IP接口到Canonical TLP的Wrapper；
4. MSI/MSI-X请求握手，把`irq_o`接到IP中断接口；
5. CDC与时序约束，包括异步时钟组和同步器标记；
6. ILA探针与板级枚举、BAR、DMA压力测试。

在没有确定FPGA型号前不提交虚假的`.xci`、`.xdc`或器件端口封装。

## 11. 已知限制与扩展方向

- 支持MRd32/MWr32单DW BAR访问，可扩展多DW和64-bit地址。
- C2H采用直接MWr64，可增加H2C MRd、Tag表和CplD重组。
- 当前没有Scatter-Gather Descriptor Ring，可增加描述符预取和Completion Queue。
- 没有多通道、MSI-X向量和性能流控，可进一步增加队列化DMA。
- 内部单拍TLP适合教学和小Payload，可改为标准多拍Streaming TLP接口。
