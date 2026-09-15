# 设计说明

## 数据面

`xadc_sampler` 例化 7 Series XADC 硬核并连续转换专用 VP/VN 通道。`xadc_acquisition_controller` 接收开始命令，只把指定数量的有效样本写入 FIFO。`xadc_axis_packer` 每 8 个 16 bit 样本组成一个 128 bit AXI4-Stream beat；末拍通过 `TKEEP` 指示有效字节，通过 `TLAST` 结束一次传输。

压力模式由 `axis_stress_source` 直接生成 128 bit Ramp 或 PRBS 数据。它和采样通路在 `xadc_xdma_core` 内二选一接到 XDMA 的 `S_AXIS_C2H_0`。源端在 `TREADY=0` 时保持 `TDATA/TKEEP/TLAST`，符合 AXI4-Stream 背压要求。

```text
XADC -> capture -> FIFO -> 16-to-128 packer --+
                                                +-> mux -> S_AXIS_C2H_0
Ramp/PRBS -> 128-bit AXI-Stream ---------------+
```

## 控制面

主机对 XDMA user BAR 的访问被 XDMA 转成 AXI-Lite 主事务，`axil_control_regs` 作为 AXI-Lite 从设备接收。主机不需要构造 MRd/MWr TLP。

| 偏移 | 名称 | 访问 | 定义 |
|---:|---|:---:|---|
| `0x000` | ID | R | 固定 `0x58414430` (`XAD0`) |
| `0x004` | VERSION | R | `0x00010000` |
| `0x008` | CONTROL | W | bit0 开始，bit1 清状态/计数 |
| `0x00C` | STATUS | R | bit0 link，1 stream busy，2 capture done，3 overflow，4 FIFO empty，5 FIFO full，6 DDS busy，7 XADC alarm，8 stress mode |
| `0x010` | TRANSFER_BYTES | R/W | 本次 C2H 字节数；XADC 模式必须为 2 的倍数 |
| `0x014` | MODE | R/W | bit0=1 压力模式；bits[2:1] 选择 Ramp/PRBS/Constant/Toggle |
| `0x018` | STRESS_SEED | R/W | 压力源起始值；PRBS 的 0 自动替换为非零种子 |
| `0x01C` | DDS_FTW | R/W | AD9833 28 bit frequency tuning word |
| `0x020` | DDS_CONTROL | R/W | bit0 三角波，bit1 写 1 触发配置 |
| `0x028/2C` | STREAM_BYTES | R | 已被 AXI-Stream 接受的 64 bit 字节计数 |
| `0x030` | CAPTURED | R | 已写入 FIFO 的样本数 |
| `0x034` | DROPPED | R | FIFO 满时丢弃的样本数 |
| `0x038` | BACKPRESSURE | R | `TVALID=1,TREADY=0` 的周期数 |

## AD9833 配置

PC 写 FTW 和波形选择后触发 `DDS_CONTROL.bit1`。`ad9833_controller` 依次发送 RESET/B28、FREQ0 LSB、FREQ0 MSB、PHASE0 和 RUN 五个 16 bit 字。频率字由软件计算：

```text
FTW = round(f_out * 2^28 / f_MCLK)
```

不同成品模块的 MCLK 可能是 25 MHz，也可能不同，运行程序时必须用 `--mclk` 指定实物标称值。

## 时钟与复位

- PCIe 100 MHz REFCLK 经 `IBUFDS_GTE2` 输入 XDMA。
- XDMA 输出 `axi_aclk` 与低有效 `axi_aresetn`，控制面、AXI-Stream、XADC DCLK 和 AD9833 SPI 控制均使用该时钟。
- FIFO 保留双时钟结构，便于以后将 XADC 换成外部高速 ADC；当前 XADC 版本两侧同为 `axi_aclk`，不存在额外采样时钟域。
- PCIe PERST# 只复位 FPGA 中的 Endpoint/XDMA 逻辑，不会替 PC 复位。AD9833 配置在链路起来后由软件显式触发。

## 带宽边界

- 128 bit × 125 MHz 的 AXI-Stream 接口理论上限为 `2.0 GB/s`。
- PCIe Gen2 x4 在线路 8b/10b 开销后为 `4 × 5 GT/s × 0.8 / 8 = 2.0 GB/s`，再扣除 TLP、流控和主机开销，应用层实测必然低于该值。
- 7 Series XADC 最高聚合采样率为约 1 MSPS；本工程每样本保存 2 bytes，因此采集数据需求约 `2 MB/s`。实际采样率由 XADC 配置与时钟决定。

压力测试与 XADC 采集解决的是两个不同问题：前者观察 PCIe/DMA 上限，后者验证真实模拟链路与数据格式。
