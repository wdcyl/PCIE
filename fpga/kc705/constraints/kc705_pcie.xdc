# KC705 board I/O used by kc705_pcie_top.
# PCIe GTX channel placement and user-clock timing are emitted by pcie_7x_0.
# Keeping them with the generated IP avoids duplicate LOC/timing constraints.

# 100 MHz PCIe reference clock, KC705 connector J8.
set_property PACKAGE_PIN U8 [get_ports sys_clk_p]
set_property PACKAGE_PIN U7 [get_ports sys_clk_n]

# PCIe PERST# from the edge connector. The board signal is active low.
set_property PACKAGE_PIN G25 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS25 [get_ports sys_rst_n]
set_property PULLUP true [get_ports sys_rst_n]

# User LEDs: link-up, Bus Master Enable, MSI enable, pending/error.
set_property PACKAGE_PIN AB8 [get_ports {led_o[0]}]
set_property PACKAGE_PIN AA8 [get_ports {led_o[1]}]
set_property PACKAGE_PIN AC9 [get_ports {led_o[2]}]
set_property PACKAGE_PIN AB9 [get_ports {led_o[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {led_o[*]}]

set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
