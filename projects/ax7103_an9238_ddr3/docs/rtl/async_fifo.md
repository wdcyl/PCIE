# async_fifo.sv

参数化Gray指针双时钟FIFO，复用于ADC时钟域到MIG UI时钟域的数据交接。写端和读端分别同步对方Gray指针，由下一指针判断满/空；`wr_overflow`与`rd_underflow`为粘滞诊断标志。

该模块只承担时钟域隔离和短时弹性，长数据块保存在板载存储中。
