#!/usr/bin/env python3
"""Compile and run all self-checking SystemVerilog regressions."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
APPLICATION_SOURCES = [
    ROOT / "rtl" / "async_fifo.sv",
    ROOT / "rtl" / "adc_pattern_source.sv",
    ROOT / "rtl" / "acquisition_controller.sv",
    ROOT / "rtl" / "c2h_dma_engine.sv",
    ROOT / "rtl" / "bar_registers.sv",
    ROOT / "rtl" / "pcie_tlp_endpoint.sv",
    ROOT / "rtl" / "tlp_tx_arbiter.sv",
    ROOT / "rtl" / "pcie_acq_top.sv",
]


def tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise SystemExit(f"error: required tool '{name}' was not found in PATH")
    return path


def compile_sv(iverilog: str, name: str, top: str, sources: list[Path]) -> Path:
    image = BUILD / f"{name}.vvp"
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
        top,
        "-o",
        str(image),
        *map(str, sources),
    ]
    print("[compile]", " ".join(compile_cmd))
    subprocess.run(compile_cmd, cwd=ROOT, check=True)
    return image


def run_sv(vvp: str, image: Path) -> None:
    print("[run]", vvp, image)
    subprocess.run([vvp, str(image)], cwd=ROOT, check=True)


def main() -> int:
    iverilog = tool("iverilog")
    vvp = tool("vvp")
    BUILD.mkdir(exist_ok=True)

    acquisition_image = compile_sv(
        iverilog,
        "pcie_acq_tb",
        "tb_pcie_acq",
        [*APPLICATION_SOURCES, ROOT / "sim" / "tb_pcie_acq.sv"],
    )
    run_sv(vvp, acquisition_image)

    integration_image = compile_sv(
        iverilog,
        "xilinx_7x_integration_tb",
        "tb_xilinx_7x_integration",
        [
            ROOT / "rtl" / "xilinx_7x_axis_bridge_64.sv",
            ROOT / "rtl" / "xilinx_7x_msi_controller.sv",
            ROOT / "sim" / "tb_xilinx_7x_integration.sv",
        ],
    )
    run_sv(vvp, integration_image)

    # The stub is deliberately excluded from Vivado. This open-source compile
    # only checks that the board top and generated-IP boundary agree.
    compile_sv(
        iverilog,
        "kc705_pcie_top_elab",
        "kc705_pcie_top",
        [
            *APPLICATION_SOURCES,
            ROOT / "rtl" / "xilinx_7x_axis_bridge_64.sv",
            ROOT / "rtl" / "xilinx_7x_msi_controller.sv",
            ROOT / "sim" / "pcie_7x_0_stub.sv",
            ROOT / "fpga" / "kc705" / "rtl" / "kc705_pcie_top.sv",
        ],
    )

    print("PASS: all simulations and KC705 top-level elaboration completed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
