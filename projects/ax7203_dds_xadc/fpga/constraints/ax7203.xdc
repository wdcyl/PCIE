###############################################################################
# ALINX AX7203 (XC7A200T-2FBG484) board constraints.
# Check the exact carrier/module revision before programming hardware.
###############################################################################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# 100 MHz PCIe reference clock and active-low PERST#.
set_property PACKAGE_PIN F10 [get_ports sys_clk_p]
set_property PACKAGE_PIN E10 [get_ports sys_clk_n]
create_clock -period 10.000 -name pcie_refclk [get_ports sys_clk_p]
set_property PACKAGE_PIN J20 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_property PULLUP TRUE [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]

# PCIe Gen2 x4 serial pairs. MGT I/O has no ordinary IOSTANDARD.
# AX7203 carrier lane order: X0Y5, X0Y4, X0Y6, X0Y7.
set_property PACKAGE_PIN D5  [get_ports {pci_exp_txp[0]}]
set_property PACKAGE_PIN C5  [get_ports {pci_exp_txn[0]}]
set_property PACKAGE_PIN D11 [get_ports {pci_exp_rxp[0]}]
set_property PACKAGE_PIN C11 [get_ports {pci_exp_rxn[0]}]
set_property PACKAGE_PIN B4  [get_ports {pci_exp_txp[1]}]
set_property PACKAGE_PIN A4  [get_ports {pci_exp_txn[1]}]
set_property PACKAGE_PIN B8  [get_ports {pci_exp_rxp[1]}]
set_property PACKAGE_PIN A8  [get_ports {pci_exp_rxn[1]}]
set_property PACKAGE_PIN B6  [get_ports {pci_exp_txp[2]}]
set_property PACKAGE_PIN A6  [get_ports {pci_exp_txn[2]}]
set_property PACKAGE_PIN B10 [get_ports {pci_exp_rxp[2]}]
set_property PACKAGE_PIN A10 [get_ports {pci_exp_rxn[2]}]
set_property PACKAGE_PIN D7  [get_ports {pci_exp_txp[3]}]
set_property PACKAGE_PIN C7  [get_ports {pci_exp_txn[3]}]
set_property PACKAGE_PIN D9  [get_ports {pci_exp_rxp[3]}]
set_property PACKAGE_PIN C9  [get_ports {pci_exp_rxn[3]}]

# Dedicated XADC header J18, pins 1/2: VP/VN, legal differential span 1 Vpp.
set_property PACKAGE_PIN L10 [get_ports xadc_vp]
set_property PACKAGE_PIN M9  [get_ports xadc_vn]

# AD9833 three-wire control on J11. Suggested wiring:
# J11-3=P16=SCLK, J11-5=R16=FSYNC#, J11-7=N17=SDATA,
# J11-39/40=3.3V, J11-1/37/38=GND.
set_property PACKAGE_PIN P16 [get_ports dds_sclk]
set_property PACKAGE_PIN R16 [get_ports dds_fsync_n]
set_property PACKAGE_PIN N17 [get_ports dds_sdata]
set_property IOSTANDARD LVCMOS33 [get_ports {dds_sclk dds_fsync_n dds_sdata}]
set_property SLEW SLOW [get_ports {dds_sclk dds_fsync_n dds_sdata}]

# LED1..LED4. LEDs are active-low on the carrier; debug levels are left raw.
set_property PACKAGE_PIN B13 [get_ports {led[0]}]
set_property PACKAGE_PIN C13 [get_ports {led[1]}]
set_property PACKAGE_PIN D14 [get_ports {led[2]}]
set_property PACKAGE_PIN D15 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]
set_false_path -to [get_ports {led[*]}]
