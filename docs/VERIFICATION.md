# 验证方案与结果

## 验证结构

`sim/tb_pcie_acq.sv`包含三个行为角色：

1. Root Complex：构造BAR0 MRd32/MWr32；
2. Host Memory：接收DMA MWr64，根据FBE/LBE写入字节数组；
3. Scoreboard：比较寄存器、Completion Header、DMA样本和统计状态。

测试不通过层次化路径修改DUT寄存器。所有配置都经过MWr，所有读取都经过MRd/CplD，DMA数据由发送TLP写入Host Memory模型。

## 自动检查

当前回归包含23项检查：

- DEVICE_ID经MRd/CplD读取；
- CplD Requester ID与Tag回传；
- Completer ID、Status和Byte Count；
- BAR寄存器MWr后MRd回读；
- 未定义BAR访问返回UR；
- 不支持的MWr64仍按Posted语义处理，不返回Completion；
- Clear Stats不会重新触发协议错误中断；
- 37个样本完成采集；
- 37个样本拆成5个MWr64；
- 奇数尾样本Byte Enable；
- Host Memory中的Ramp数据连续；
- DMA Byte Count；
- DMA完成中断；
- IRQ W1C；
- 随机发送背压；
- 背压期间TLP稳定；
- 4 KiB边界自动拆包；
- 边界前后数据顺序；
- 持续背压导致FIFO溢出；
- Dropped Count递增；
- 解除背压后DMA完成；
- Overflow状态保持；
- 所有TLP类型和Host Memory地址范围检查。

## 已验证结果

Icarus Verilog命令：

```bash
python scripts/run_sim.py
```

基线结果：

```text
=== Regression summary ===
checks=23 errors=0 cpl=6 dma_packets=15 dma_bytes=226
ALL TESTS PASSED
```

GitHub Actions在每次Push和Pull Request时运行同一脚本，防止本地和CI使用不同测试入口。

## 波形建议

`build/pcie_acq.vcd`可重点观察：

- `rx_valid/rx_ready`与MRd/MWr Header；
- `cpl_tlp_valid/cpl_tlp_ready`；
- `fifo_wr_en/fifo_full/fifo_rd_en/fifo_rd_valid`；
- `dma_tlp_valid/dma_tlp_ready`；
- `status`、`irq`、`captured_count`、`dropped_count`。

## 板级验证清单

选择板卡后需要另外完成：

- LTSSM进入L0；
- 协商速率与Lane Width符合配置；
- `lspci -vv`能读取Vendor/Device ID和BAR；
- BAR寄存器读写；
- MSI/MSI-X；
- 长时间DMA数据一致性；
- 不同Payload和背压条件下的吞吐率；
- ILA捕获异常时的TLP/FIFO状态。

板级项目只能报告实际完成的检查；本文的自动回归结果属于RTL事务层与数据通路结果。
