create_clock -name clk -period 8.0 [get_ports {clk}]
create_clock -name lan_rx -period 8.0 [get_ports {lan_rgmii_rx_clk}]
create_clock -name wan_rx -period 8.0 [get_ports {wan_rgmii_rx_clk}]
set_clock_groups -asynchronous -group {clk} -group {lan_rx} -group {wan_rx}
