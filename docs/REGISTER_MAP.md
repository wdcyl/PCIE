# BAR0寄存器表

BAR0内部地址空间为4 KiB。当前实现使用低`0x000-0x038`。

| Offset | 名称 | 属性 | Reset | 说明 |
|---:|---|---|---:|---|
| `0x000` | DEVICE_ID | RO | `0x50434945` | ASCII `PCIE` |
| `0x004` | VERSION | RO | `0x00010000` | v1.0.0 |
| `0x008` | CONTROL | WO/Pulse | 0 | bit0 Start；bit3 Clear Stats；bit1/2保留 |
| `0x00C` | STATUS | RO | - | 系统状态 |
| `0x010` | SAMPLE_COUNT | RW | 1024 | 一次采集的16-bit样本数量 |
| `0x014` | PATTERN | RW | 0 | `[1:0]`模式，`[31:16]`常量值 |
| `0x018` | DMA_ADDR_LO | RW | 0 | 主机目的地址低32位，必须4-byte对齐 |
| `0x01C` | DMA_ADDR_HI | RW | 0 | 主机目的地址高32位 |
| `0x020` | IRQ_STATUS | RO/W1C | 0 | 中断状态，写1清除 |
| `0x024` | IRQ_ENABLE | RW | 0 | 中断使能 |
| `0x028` | RX_TLP_COUNT | RO | 0 | 接收TLP数量 |
| `0x02C` | TX_TLP_COUNT | RO | 0 | Clear Stats以来Completion加DMA TLP数量 |
| `0x030` | ERROR_COUNT | RO | 0 | Clear Stats以来Endpoint错误加Dropped Count |
| `0x034` | BYTE_COUNT_LO | RO | 0 | Clear Stats以来DMA有效字节数低32位 |
| `0x038` | BYTE_COUNT_HI | RO | 0 | Clear Stats以来DMA有效字节数高32位 |

## CONTROL

CONTROL命令只持续一个`pcie_clk`周期，不保存写入值。

| Bit | 名称 | 作用 |
|---:|---|---|
| 0 | START | 按当前配置启动采集和C2H DMA |
| 1 | Reserved | 当前版本不使用 |
| 2 | Reserved | 当前版本不使用 |
| 3 | CLEAR_STATS | 清除DMA统计并清采集状态；建议空闲时使用 |

## STATUS

| Bit | 名称 |
|---:|---|
| 0 | Acquisition Busy |
| 1 | Acquisition Done |
| 2 | Acquisition Overflow |
| 3 | DMA Busy |
| 4 | DMA Done |
| 5 | FIFO Empty |
| 6 | FIFO Full |
| 7 | IRQ Asserted |
| `[23:16]` | PCIe侧FIFO Level的低8位 |

## IRQ_STATUS / IRQ_ENABLE

| Bit | 事件 |
|---:|---|
| 0 | DMA完成 |
| 1 | 采集FIFO溢出 |
| 2 | TLP格式错误或未定义BAR访问 |

## 软件启动顺序

```text
1. 写 SAMPLE_COUNT
2. 写 PATTERN
3. 写 DMA_ADDR_LO / DMA_ADDR_HI
4. 写 IRQ_ENABLE
5. 等待配置跨域稳定
6. CONTROL.START = 1
7. 轮询 STATUS.DMA_DONE 或等待中断
8. 读取 BYTE_COUNT / ERROR_COUNT
9. 向 IRQ_STATUS 对应位写1清中断
```

`DMA_ADDR`必须4-byte对齐；当前版本不会自动修正软件传入的未对齐语义。`PATTERN`和`SAMPLE_COUNT`在Start前至少稳定两个ADC时钟，并在本次采集期间保持不变。
