#!/usr/bin/env python3
"""Compile and run the portable RTL core with Icarus Verilog."""
from pathlib import Path
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
iverilog=shutil.which("iverilog")
vvp=shutil.which("vvp")
if not iverilog or not vvp:
    sys.exit("iverilog/vvp not found; install Icarus Verilog or use Vivado xsim")
sources=[root/"rtl/async_fifo.sv",root/"rtl/xadc_acquisition_controller.sv",
         root/"rtl/xadc_axis_packer.sv",root/"rtl/axis_stress_source.sv",
         root/"rtl/axil_control_regs.sv",root/"rtl/xadc_xdma_core.sv",
         root/"sim/tb_core.sv"]
build=root/"build"; build.mkdir(exist_ok=True)
out=build/"core_tb.vvp"
subprocess.run([iverilog,"-g2012","-s","tb_core","-o",str(out),*map(str,sources)],check=True)
subprocess.run([vvp,str(out)],check=True)
