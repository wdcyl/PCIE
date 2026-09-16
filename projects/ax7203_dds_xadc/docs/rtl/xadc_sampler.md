# `xadc_sampler.sv`

源码：[rtl/xadc_sampler.sv](../../rtl/xadc_sampler.sv)

## 模块定位

该模块直接例化7 Series FPGA内部的 `XADC` 硬核，把AX7203 J18上的专用 `VP/VN` 模拟输入转换成12 bit数字样本。

## 端口

| 端口 | 方向 | 宽度 | 说明 |
|---|:---:|---:|---|
| `dclk_i` | 输入 | 1 | XADC DRP和本模块输出寄存器时钟 |
| `rst_ni` | 输入 | 1 | 低有效复位，内部反相后送XADC `RESET` |
| `vp_i/vn_i` | 输入 | 1+1 | 专用模拟差分输入 |
| `sample_o` | 输出 | 12 | 最新一次VP/VN转换的原始12 bit码 |
| `sample_valid_o` | 输出 | 1 | 新样本有效的单周期脉冲 |
| `alarm_o` | 输出 | 1 | 任意XADC告警或过温告警 |
| `busy_o` | 输出 | 1 | XADC硬核正在转换 |

## XADC初始化参数

| 参数 | 值 | 作用 |
|---|---:|---|
| `INIT_40` | `0x0000` | 外部通道不启用平均 |
| `INIT_41` | `0x2EF0` | 连续Sequencer模式并屏蔽不需要的内部告警 |
| `INIT_42` | `0x0500` | DCLK除5；125 MHz输入时ADC时钟为25 MHz |
| `INIT_48` | `0x0800` | CHSEL位11，选择专用VP/VN通道3 |
| `INIT_49` | `0x0000` | 不选择VAUX通道 |
| `INIT_4A~4F` | 0 | 无平均、单极性、默认采集时间 |

`VAUXP/VAUXN`全部绑0，因为本工程只使用专用VP/VN，不使用辅助模拟通道。

## DRP自动读取

XADC在一次转换结束时拉高 `EOC`。模块把：

```text
DEN   = EOC
DADDR = {2'b00, CHANNEL}
DWE   = 0
```

这样每次转换完成后自动发起对应状态寄存器的DRP读操作。`DRDY`表示读数据有效，`DO[15:4]`就是12 bit转换码。

只有在：

```text
DRDY == 1 && CHANNEL == 3
```

时，模块才更新 `sample_o` 并产生 `sample_valid_o`。其他通道即使产生DRP结果也不会进入采集链路。

## 样本格式

`sample_o`是XADC原始无符号码：

```text
0x000 -> 输入接近量程下限
0xFFF -> 输入接近量程上限
```

本模块不做电压换算、偏置校正或滤波。PC端要结合参考电压和前端电路把原始码换算为实际电压。

## 告警

```text
alarm_o = OR(ALM[7:0]) | OT
```

它表示硬核任一告警或过温，不代表输入信号一定越界。实际调试时要结合XADC配置和状态寄存器判断来源。

## 注意事项

- `VP/VN`是模拟专用引脚，不是普通3.3 V GPIO。
- 输入幅值、共模和极性必须符合XADC规范；本模块没有数字方式的过压保护。
- 若修改 `axi_aclk` 频率，必须重新计算 `INIT_42`，使ADC时钟保持在器件允许范围内。
- `vendor_stubs.sv`中的XADC只是编译桩，不能模拟真实模数转换。
