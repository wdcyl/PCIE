# axi_test_source.sv

内部测试源每个128-bit数据拍包含四个连续32-bit计数值，从`seed_i`开始。它以ready/valid握手运行，可在不接AN9238时验证采集写入、存储、XDMA读取和PC校验整条数字通路。
