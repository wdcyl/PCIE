# AXI-Lite寄存器表

| 偏移 | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `0x000` | ID | RO | 固定`0x41443932`，ASCII为`AD92` |
| `0x004` | VERSION | RO | 当前`0x00020000` |
| `0x008` | CONTROL | WO | bit0启动；bit1清状态计数 |
| `0x00C` | STATUS | RO | 链路、校准、忙、完成和错误状态 |
| `0x010` | CAPTURE_BYTES | RW | 采集字节数，必须为16的倍数 |
| `0x014` | BUFFER_BASE | RW | 存储区基地址，必须16字节对齐 |
| `0x018` | MODE | RW | bit0：0=ADC，1=内部Ramp |
| `0x01C` | TEST_SEED | RW | Ramp起始32-bit值 |
| `0x020` | CAPTURED_PAIRS | RO | 已采集/生成的32-bit数据字数 |
| `0x024` | WRITTEN_LO | RO | 已写入字节计数低32位 |
| `0x028` | WRITTEN_HI | RO | 已写入字节计数高32位 |

`STATUS`位定义：bit0 `LINK_UP`，bit1 `CALIB_DONE`，bit2 `CAPTURE_BUSY`，bit3 `WRITER_READY`，bit4 `CAPTURE_DONE`，bit5 `OVERFLOW`，bit6 `AXI_ERROR`，bit7 `BUFFER_READY`，bit8 `TEST_MODE`。

推荐顺序：写`CONTROL.CLEAR`，配置长度/地址/模式，确认bit0和bit1为1，写`CONTROL.START`，等待bit7或错误位，随后通过C2H读取相同地址和长度。
