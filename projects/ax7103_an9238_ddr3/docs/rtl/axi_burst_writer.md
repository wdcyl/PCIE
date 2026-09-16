# axi_burst_writer.sv

写状态机为`IDLE → PREP → AW → W → B`。`PREP`按剩余长度、最大64拍和下一个4 KiB边界计算本次突发；`AW`发送地址；`W`传送128-bit数据并产生`WLAST`；`B`检查响应后继续下一突发或结束。

基地址和长度必须16字节对齐。`abort_i`用于采集溢出时终止等待，非OKAY的`BRESP`会置`error_o`。
