`include "hw_clk_cfg.v"
module full_top (
    input  wire        clk,
    input  wire        rstn,
    output wire        uart0_txd,
    input  wire        uart0_rxd,
    output wire        smc_sck,
    output wire        smc_sdo,
    input  wire        smc_sdi,
    output wire        smc_csn,
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
    wire [1:0]  nrv_smc_csn;
    wire clk_dp;
    wire clk_nrv;
    wire pll_lock;

    PLLA u_pll (
        .LOCK(pll_lock),
        .CLKOUT0(clk_dp),
        .CLKOUT1(clk_nrv),
        .CLKOUT2(), .CLKOUT3(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUT(), .MDRDO(),
        .CLKIN(clk), .CLKFB(1'b0),
        .RESET(1'b0), .PLLPWD(1'b0), .RESET_I(1'b0), .RESET_O(1'b0),
        .PSSEL(3'd0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'd0), .SSCMDSEL_FRAC(3'd0),
        .MDCLK(1'b0), .MDOPC(2'd0), .MDAINC(1'b0), .MDWDI(8'd0)
    );
    defparam u_pll.FCLKIN = "50";
    defparam u_pll.IDIV_SEL = 2;
    defparam u_pll.FBDIV_SEL = 5;
    defparam u_pll.CLKFB_SEL = "INTERNAL";
    defparam u_pll.MDIV_SEL = `CLK_MDIV;
    defparam u_pll.ODIV0_SEL = `CLK_ODIV0;
    defparam u_pll.ODIV0_FRAC_SEL = `CLK_ODIV0_FRAC;
    defparam u_pll.ODIV1_SEL = `CLK_ODIV1;
    defparam u_pll.CLKOUT0_EN = "TRUE";
    defparam u_pll.CLKOUT1_EN = "TRUE";

    neorv32_setup_25k #(
        .CLOCK_FREQUENCY(50000000),
        .IMEM_SIZE(2048),
        .DMEM_SIZE(1024)
    ) u_nrv (
        .clk_i(clk_nrv),
        .rstn_i(rstn),
        .gpio_o(nrv_gpio),
        .uart0_txd_o(uart0_txd),
        .uart0_rxd_i(uart0_rxd),
        .smc_sck_o(smc_sck),
        .smc_sdo_o(smc_sdo),
        .smc_sdi_i(smc_sdi),
        .smc_csn_o(nrv_smc_csn),
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
    assign smc_csn = nrv_smc_csn[0];

    bridge_top #(
        .MAC_TARGET("GOWIN")
    ) u_bridge (
        .clk(clk_dp),
        .rst_n(rstn),
        .gtx_clk(clk_dp),
        .gtx_clk90(clk_dp),
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
