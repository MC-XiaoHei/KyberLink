module kyberlink_tb_wrap (
    input wire clk,
    input wire rst_n,
    output wire led,
    output wire tag_ok,

    input wire [3:0] lan_rgmii_rxd,
    input wire lan_rgmii_rx_ctl,
    output wire [3:0] lan_rgmii_txd,
    output wire lan_rgmii_tx_ctl,

    input wire [3:0] wan_rgmii_rxd,
    input wire wan_rgmii_rx_ctl,
    output wire [3:0] wan_rgmii_txd,
    output wire wan_rgmii_tx_ctl,

    input wire spi_sck,
    input wire spi_mosi,
    output wire spi_miso,
    input wire spi_csn
);

    kyberlink_top u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .led(led),
        .tag_ok(tag_ok),
        .lan_rgmii_rx_clk(clk),
        .lan_rgmii_rxd(lan_rgmii_rxd),
        .lan_rgmii_rx_ctl(lan_rgmii_rx_ctl),
        .lan_rgmii_tx_clk(),
        .lan_rgmii_txd(lan_rgmii_txd),
        .lan_rgmii_tx_ctl(lan_rgmii_tx_ctl),
        .wan_rgmii_rx_clk(clk),
        .wan_rgmii_rxd(wan_rgmii_rxd),
        .wan_rgmii_rx_ctl(wan_rgmii_rx_ctl),
        .wan_rgmii_tx_clk(),
        .wan_rgmii_txd(wan_rgmii_txd),
        .wan_rgmii_tx_ctl(wan_rgmii_tx_ctl),
        .spi_sck(spi_sck),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_csn(spi_csn)
    );

endmodule
