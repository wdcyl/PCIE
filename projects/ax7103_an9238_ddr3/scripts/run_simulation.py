from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
build = root / "build" / "sim"
build.mkdir(parents=True, exist_ok=True)
iverilog = shutil.which("iverilog")
vvp = shutil.which("vvp")
if not iverilog or not vvp:
    raise SystemExit("Icarus Verilog is required (iverilog and vvp on PATH)")

rtl = [
    root / "rtl" / "async_fifo.sv",
    root / "rtl" / "an9238_capture.sv",
    root / "rtl" / "fifo_stream_adapter.sv",
    root / "rtl" / "axi_test_source.sv",
    root / "rtl" / "axi_burst_writer.sv",
    root / "rtl" / "axil_acquisition_regs.sv",
    root / "rtl" / "acquisition_ddr_core.sv",
    root / "fpga" / "rtl" / "acquisition_ddr_bd_adapter.sv",
]
elab = build / "full_elab.vvp"
subprocess.run([iverilog, "-g2012", "-Wall", "-s", "acquisition_ddr_bd_adapter", "-o", str(elab), *map(str, rtl)], check=True)

image = build / "tb_rtl.vvp"
tb_sources = [root / "rtl" / "an9238_capture.sv", root / "rtl" / "axi_burst_writer.sv", root / "sim" / "tb_rtl.sv"]
subprocess.run([iverilog, "-g2012", "-Wall", "-s", "tb_rtl", "-o", str(image), *map(str, tb_sources)], check=True)
result = subprocess.run([vvp, str(image)], text=True)
sys.exit(result.returncode)
