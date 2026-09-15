# 验证计划与结果记录

## 当前已具备的检查

核心级 testbench `sim/tb_core.sv` 覆盖：

- AXI-Lite 写入传输长度、模式和开始命令
- 10 个 16 bit XADC 样本打包成 20 bytes、2 个 AXI beat
- 64 bytes Ramp 数据产生 4 个完整 AXI beat
- 末拍 `TKEEP/TLAST` 与累计字节数

运行：

```bash
python scripts/run_simulation.py
```

该仿真不模拟 PCIe PHY、链路训练或 XDMA 内部事务，只验证自研业务 RTL。仓库提交时若本机没有 Icarus/Vivado，结果应记录为“未运行”，不能写成通过。

## 建议的逐级上板验证

1. **枚举**：记录 `lspci -vv` 中 BDF、BAR、LnkCap/LnkSta。
2. **寄存器**：读取 ID `0x58414430`，回读 MODE、TRANSFER_BYTES 和 DDS_FTW。
3. **Ramp**：4 KiB 后逐字比较；通过后测试 64 MiB，记录 5 次速度的均值和范围。
4. **PRBS**：至少 256 MiB 连续校验，记录错误数。
5. **背压**：延迟启动/暂停主机读取，确认 AXI 数据稳定且 BACKPRESSURE 增长。
6. **XADC 静态**：VP 接已知直流电压，确认码值与输入近似线性。
7. **DDS 波形**：10 kHz 起步，用示波器确认幅度/偏置安全后接 XADC；保存原始数据并在 PC 绘图/FFT。
8. **长稳**：连续采集 30 min，记录 dropped、错误和链路重训练。

## 结果记录模板

| 项目 | 条件 | 结果 | 证据 |
|---|---|---|---|
| Vivado synthesis | 版本/器件 | 未运行 | log 路径 |
| Timing | user clock | 未运行 | WNS/TNS |
| PCIe enumeration | PC/OS | 未运行 | `lspci -vv` |
| Ramp 64 MiB | Gen/width | 未运行 | MB/s、errors |
| PRBS 256 MiB | seed | 未运行 | errors |
| XADC 10 kHz | amplitude/offset | 未运行 | 数据文件/频谱图 |

只有填入真实命令输出、日志或截图后，才适合在简历中写“上板验证通过”及具体吞吐率。
