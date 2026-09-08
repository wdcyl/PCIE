`ifndef PCIE_DEFS_SVH
`define PCIE_DEFS_SVH

// Fmt/Type values, encoded exactly as DW0[31:24].
`define PCIE_TLP_MRD32 8'h00
`define PCIE_TLP_MRD64 8'h20
`define PCIE_TLP_MWR32 8'h40
`define PCIE_TLP_MWR64 8'h60
`define PCIE_TLP_CPL   8'h0a
`define PCIE_TLP_CPLD  8'h4a

// Completion Status, DW1[15:13].
`define PCIE_CPL_SC    3'b000
`define PCIE_CPL_UR    3'b001
`define PCIE_CPL_CRS   3'b010
`define PCIE_CPL_CA    3'b100

`endif
