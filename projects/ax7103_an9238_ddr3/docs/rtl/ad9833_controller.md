# ad9833_controller.sv

AD9833三线串行控制器。`apply_i`到来时锁存28-bit FTW和波形选择，随后依次发送5个16-bit控制字。发送期间`busy_o`保持为1，最后一个控制字完成后产生单周期`done_pulse_o`。

`CLK_DIV`控制SCLK分频。模块在SCLK上升沿更新SDATA，使数据在AD9833使用的下降沿前保持稳定；每个控制字用独立的低有效FSYNC帧发送。忙期间再次写`apply_i`不会中断当前配置。

主要端口：

| 端口 | 说明 |
|---|---|
| `ftw_i[27:0]` | 频率调谐字，公式为`round(fout*2^28/MCLK)` |
| `triangle_i` | 0为正弦，1为三角波 |
| `sclk_o` | AD9833串行时钟 |
| `fsync_no` | 低有效帧选通 |
| `sdata_o` | 串行配置数据 |

