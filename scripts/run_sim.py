#!/usr/bin/env python3
"""Compile and run the self-checking SystemVerilog regression."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise SystemExit(f"error: required tool '{name}' was not found in PATH")
    return path


def main() -> int:
    iverilog = tool("iverilog")
    vvp = tool("vvp")
    BUILD.mkdir(exist_ok=True)
    image = BUILD / "pcie_acq_tb.vvp"

    sources = [
        ROOT / "rtl" / "async_fifo.sv",
        ROOT / "rtl" / "adc_pattern_source.sv",
        ROOT / "rtl" / "acquisition_controller.sv",
        ROOT / "rtl" / "c2h_dma_engine.sv",
        ROOT / "rtl" / "bar_registers.sv",
        ROOT / "rtl" / "pcie_tlp_endpoint.sv",
        ROOT / "rtl" / "tlp_tx_arbiter.sv",
        ROOT / "rtl" / "pcie_acq_top.sv",
        ROOT / "sim" / "tb_pcie_acq.sv",
    ]
    missing = [str(path) for path in sources if not path.exists()]
    if missing:
        raise SystemExit("error: missing source files:\n  " + "\n  ".join(missing))

    compile_cmd = [
        iverilog,
        "-g2012",
        "-Wall",
        "-I",
        str(ROOT / "rtl"),
        "-s",
        "tb_pcie_acq",
        "-o",
        str(image),
        *map(str, sources),
    ]
    print("[compile]", " ".join(compile_cmd))
    subprocess.run(compile_cmd, cwd=ROOT, check=True)

    print("[run]", vvp, image)
    return subprocess.run([vvp, str(image)], cwd=ROOT, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
