# PC端程序

`pcie_capture.c`面向Linux XDMA字符设备。它通过`/dev/xdma0_user`配置寄存器，等待缓存就绪，然后对`/dev/xdma0_c2h_0`执行带AXI地址偏移的`pread`。

```bash
make -C software
sudo software/pcie_capture --mode ramp --bytes 67108864 --seed 0 --out ramp.bin
sudo software/pcie_capture --mode adc --freq 100000 --mclk 25000000 --bytes 1048576 --out adc.bin
python software/plot_capture.py adc.bin --count 4096 --csv adc.csv
```

Ramp模式逐32-bit递增，程序自动逐字校验；ADC模式检查两个保留高4位为0。程序分别统计采集写入阶段和C2H读取阶段速率。Windows可复用ALINX官方`PCIE_test`提供的XDMA驱动与Qt测速框架，但需要按本工程寄存器表增加启动和状态轮询。


`--freq`与`--mclk`用于计算AD9833频率调谐字，`--triangle`选择三角波；不传`--freq`时不会重新配置AD9833。先确认模块实际MCLK，不能默认所有AD9833小板都是25 MHz。
