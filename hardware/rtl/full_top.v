module full_top (
    input  wire        clk,
    input  wire        rstn,
    output wire        uart0_txd,
    input  wire        uart0_rxd,
    output wire        spi_clk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_csn,
    output wire        gpio_led,
    input  wire        lan_rgmii_rx_clk,
    input  wire [3:0]  lan_rgmii_rxd,
    input  wire        lan_rgmii_rx_ctl,
    output wire        lan_rgmii_tx_clk,
    output wire [3:0]  lan_rgmii_txd,
    output wire        lan_rgmii_tx_ctl,
    input  wire        wan_rgmii_rx_clk,
    input  wire [3:0]  wan_rgmii_rxd,
    input  wire        wan_rgmii_rx_ctl,
    output wire        wan_rgmii_tx_clk,
    output wire [3:0]  wan_rgmii_txd,
    output wire        wan_rgmii_tx_ctl,
    output wire        eth_rstn
);

    wire [31:0] nrv_gpio;
    wire [31:0] nrv_xbus_adr;
    wire [31:0] nrv_xbus_dat_o;
    wire [31:0] nrv_xbus_dat_i;
    wire        nrv_xbus_we;
    wire        nrv_xbus_sel;
    wire        nrv_xbus_stb;
    wire        nrv_xbus_cyc;
    wire        nrv_xbus_ack;
    wire        nrv_xbus_err;
    wire [7:0]  nrv_spi_csn;

    neorv32_setup_25k #(
        .CLOCK_FREQUENCY(50000000),
        .IMEM_SIZE(16384),
        .DMEM_SIZE(8192)
    ) u_nrv (
        .clk_i(clk),
        .rstn_i(rstn),
        .gpio_o(nrv_gpio),
        .uart0_txd_o(uart0_txd),
        .uart0_rxd_i(uart0_rxd),
        .spi_clk_o(spi_clk),
        .spi_dat_o(spi_mosi),
        .spi_dat_i(spi_miso),
        .spi_csn_o(nrv_spi_csn),
        .xbus_adr_o(nrv_xbus_adr),
        .xbus_dat_o(nrv_xbus_dat_o),
        .xbus_we_o(nrv_xbus_we),
        .xbus_sel_o(nrv_xbus_sel),
        .xbus_stb_o(nrv_xbus_stb),
        .xbus_cyc_o(nrv_xbus_cyc),
        .xbus_dat_i(nrv_xbus_dat_i),
        .xbus_ack_i(nrv_xbus_ack),
        .xbus_err_i(nrv_xbus_err)
    );

    assign gpio_led = nrv_gpio[0];
    assign spi_csn = nrv_spi_csn[0];

    bridge_top #(
        .MAC_TARGET("GOWIN")
    ) u_bridge (
        .clk(clk),
        .rst_n(rstn),
        .gtx_clk(clk),
        .gtx_clk90(clk),
        .key(256'd0),
        .cfg_spi(32'h11223344),
        .cfg_iv(96'h000000000000000000000001),
        .seq_in(32'd0),
        .cfg_src_ip(32'h0A000001),
        .cfg_dst_ip(32'h0A000002),
        .cfg_src_port(16'd4500),
        .cfg_dst_port(16'd4500),
        .lan_rgmii_rx_clk(lan_rgmii_rx_clk),
        .lan_rgmii_rxd(lan_rgmii_rxd),
        .lan_rgmii_rx_ctl(lan_rgmii_rx_ctl),
        .lan_rgmii_tx_clk(lan_rgmii_tx_clk),
        .lan_rgmii_txd(lan_rgmii_txd),
        .lan_rgmii_tx_ctl(lan_rgmii_tx_ctl),
        .wan_rgmii_rx_clk(wan_rgmii_rx_clk),
        .wan_rgmii_rxd(wan_rgmii_rxd),
        .wan_rgmii_rx_ctl(wan_rgmii_rx_ctl),
        .wan_rgmii_tx_clk(wan_rgmii_tx_clk),
        .wan_rgmii_txd(wan_rgmii_txd),
        .wan_rgmii_tx_ctl(wan_rgmii_tx_ctl)
        
    );

    assign nrv_xbus_dat_i = 32'd0;
    assign nrv_xbus_ack = 1'b0;
    assign nrv_xbus_err = 1'b0;

endmodule
