create_clock -name clk -period 20.0 [get_ports {clk}]
create_clock -name lan_rx -period 8.0 [get_ports {lan_rgmii_rx_clk}]
create_clock -name wan_rx -period 8.0 [get_ports {wan_rgmii_rx_clk}]
create_generated_clock -name clk_sys -source [get_ports {clk}] -multiply_by 5 -divide_by 2 [get_pins {u_pll/pll_inst/CLKOUT0}]
set_clock_groups -asynchronous -group {clk_sys} -group {lan_rx} -group {wan_rx}
set_false_path -from [get_clocks {lan_rx}] -to [get_clocks {clk_sys}]
set_false_path -from [get_clocks {wan_rx}] -to [get_clocks {clk_sys}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {lan_rx}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {wan_rx}]
