# 上板流程

1. 不连接AN9238，先烧写bitstream并确认MIG的`init_calib_complete`和PCIe `user_lnk_up`均为1。
2. 冷启动主机，使用`lspci -nn`确认Xilinx Endpoint，加载AMD/Xilinx `dma_ip_drivers`中的XDMA驱动。
3. 运行内部Ramp测试，依次验证BAR控制、存储写入、C2H读取和数据一致性。
4. 断电后将AN9238插入AX7103 J13；将AD9833的SCLK/FSYNC/SDATA接到J11的3/4/5脚并共地，模拟输出接AN9238 CH0 SMA。
5. 先用示波器确认AD9833低频、低幅输出，确保幅度、偏置和共模满足AN9238输入范围。
6. 再输入低频、低幅正弦波，采集1 MiB并用`plot_capture.py`观察两路码值，再逐步提高频率。
7. 最后进行长块传输、重复启动、不同基地址以及错误恢复测试。

不要让ADC输入悬空来判断采集是否正确；悬空输入只会受到噪声和偏置影响。PCIe插拔、AN9238插拔和板卡连接均应断电操作。
