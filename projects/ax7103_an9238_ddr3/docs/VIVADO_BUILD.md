# Vivado工程与IP配置

## 自动重建

```tcl
vivado -mode batch -source fpga/tcl/create_project.tcl
```

脚本创建XC7A100T-FGG484-2工程和Block Design，加入自研RTL并生成以下IP：XDMA、MIG 7 Series、AXI Interconnect、两个AXI Clock Converter、两个Clocking Wizard和Processor System Reset。

## 必须人工复核

不同Vivado版本会改变部分XDMA属性名。脚本对关键属性使用强校验，属性不存在时直接报错，而不是静默生成错误工程。首次打开工程必须检查：

1. XDMA显示Endpoint、Gen2 x4、AXI Memory Mapped、128 bit/125 MHz。
2. PCIe Block Location为X0Y0，参考时钟100 MHz。
3. MIG器件与板卡为XC7A100T-FGG484-2，DDR3数据宽度32 bit，AXI数据宽度256 bit，校准无报错。
4. Address Editor中XDMA和采集写主机都能访问MIG存储区；AXI-Lite能访问控制寄存器。
5. `validate_bd_design`、综合DRC和时序报告无Critical Warning。

`ax7103_mig.prj`来自AX7103官方PCIe/DDR3案例。若实物板卡版本、存储颗粒或速度等级不同，应在MIG GUI中按对应原理图重新生成，不能盲目沿用。


## 新增板级端口

Block Design同时导出`dds_sclk`、`dds_fsync_n`和`dds_sdata`，约束到AX7103 J11的P16、R17、R16。AN9238继续使用J13以及`adc_clk_ch0/1`、`adc_ch0/1`端口。生成bitstream前应结合具体板卡版本原理图复核管脚。
