`include "hw_clk_cfg.v"
module full_top (
    input  wire        clk,
    (* syn_maxfan = 300 *) input wire rstn,
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
    wire [255:0] enc_key_w;
    wire [255:0] dec_key_w;
    wire [31:0]  enc_spi_w, enc_seq0_w, dec_spi_w, dec_seq0_w;
    wire [95:0]  enc_salt_w, dec_salt_w;
    wire [31:0]  cfg_src_ip_w, cfg_dst_ip_w;
    wire [15:0]  cfg_src_port_w, cfg_dst_port_w;
    wire [47:0]  cfg_src_mac_w, cfg_dst_mac_w;
    wire [1:0]   sa_en_w;
    wire [31:0]  bridge_seq_out;
    wire clk_nrv;
    wire clk_tx;
    wire clk_tx90;
    wire pll_data_lock;
    wire pll_cpu_lock;
    wire pll_mac_lock;

    PLLA u_pll_data (
        .LOCK(pll_data_lock),
        .CLKOUT0(), .CLKOUT1(clk_dp),
        .CLKOUT2(), .CLKOUT3(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUT(), .MDRDO(),
        .CLKIN(clk), .CLKFB(1'b0),
        .RESET(1'b0), .PLLPWD(1'b0), .RESET_I(1'b0), .RESET_O(1'b0),
        .PSSEL(3'd0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'd0), .SSCMDSEL_FRAC(3'd0),
        .MDCLK(1'b0), .MDOPC(2'd0), .MDAINC(1'b0), .MDWDI(8'd0)
    );
    defparam u_pll_data.FCLKIN = "50";
    defparam u_pll_data.IDIV_SEL = 2;
    defparam u_pll_data.FBDIV_SEL = 5;
    defparam u_pll_data.CLKFB_SEL = "INTERNAL";
    defparam u_pll_data.MDIV_SEL = `DATA_MDIV;
    defparam u_pll_data.ODIV1_SEL = `DATA_ODIV1;
    defparam u_pll_data.CLKOUT1_EN = "TRUE";

    PLLA u_pll_cpu (
        .LOCK(pll_cpu_lock),
        .CLKOUT0(clk_nrv),
        .CLKOUT1(),
        .CLKOUT2(), .CLKOUT3(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUT(), .MDRDO(),
        .CLKIN(clk), .CLKFB(1'b0),
        .RESET(1'b0), .PLLPWD(1'b0), .RESET_I(1'b0), .RESET_O(1'b0),
        .PSSEL(3'd0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'd0), .SSCMDSEL_FRAC(3'd0),
        .MDCLK(1'b0), .MDOPC(2'd0), .MDAINC(1'b0), .MDWDI(8'd0)
    );
    defparam u_pll_cpu.FCLKIN = "50";
    defparam u_pll_cpu.IDIV_SEL = 2;
    defparam u_pll_cpu.FBDIV_SEL = 5;
    defparam u_pll_cpu.CLKFB_SEL = "INTERNAL";
    defparam u_pll_cpu.MDIV_SEL = `CPU_MDIV;
    defparam u_pll_cpu.ODIV0_SEL = `CPU_ODIV0;
    defparam u_pll_cpu.ODIV0_FRAC_SEL = `CPU_ODIV0_FRAC;
    defparam u_pll_cpu.ODIV1_SEL = `CPU_ODIV1;
    defparam u_pll_cpu.CLKOUT0_EN = "TRUE";
    defparam u_pll_cpu.CLKOUT1_EN = "FALSE";

    PLLA u_pll_mac (
        .LOCK(pll_mac_lock),
        .CLKOUT0(clk_tx),
        .CLKOUT1(clk_tx90),
        .CLKOUT2(), .CLKOUT3(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUT(), .MDRDO(),
        .CLKIN(clk), .CLKFB(1'b0),
        .RESET(1'b0), .PLLPWD(1'b0), .RESET_I(1'b0), .RESET_O(1'b0),
        .PSSEL(3'd0), .PSDIR(1'b0), .PSPULSE(1'b0),
        .SSCPOL(1'b0), .SSCON(1'b0), .SSCMDSEL(7'd0), .SSCMDSEL_FRAC(3'd0),
        .MDCLK(1'b0), .MDOPC(2'd0), .MDAINC(1'b0), .MDWDI(8'd0)
    );
    defparam u_pll_mac.FCLKIN = "50";
    defparam u_pll_mac.IDIV_SEL = 2;
    defparam u_pll_mac.FBDIV_SEL = 5;
    defparam u_pll_mac.CLKFB_SEL = "INTERNAL";
    defparam u_pll_mac.MDIV_SEL = `MAC_MDIV;
    defparam u_pll_mac.ODIV0_SEL = `MAC_ODIV0;
    defparam u_pll_mac.ODIV0_FRAC_SEL = `MAC_ODIV0_FRAC;
    defparam u_pll_mac.ODIV1_SEL = `MAC_ODIV1;
    defparam u_pll_mac.CLKOUT0_EN = "TRUE";
    defparam u_pll_mac.CLKOUT1_EN = "TRUE";

    neorv32_setup_25k #(
        .CLOCK_FREQUENCY(`CPU_CLOCK_HZ),
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

    wire [31:0] bc_dat_o;
    wire        bc_ack_o;
    wire        bc_err_o;

    bridge_ctrl u_bc (
        .clk(clk_nrv),
        .rst_n(rstn),
        .xbus_adr_i(nrv_xbus_adr),
        .xbus_dat_i(nrv_xbus_dat_o),
        .xbus_we_i(nrv_xbus_we),
        .xbus_stb_i(nrv_xbus_stb),
        .xbus_cyc_i(nrv_xbus_cyc),
        .xbus_dat_o(bc_dat_o),
        .xbus_ack_o(bc_ack_o),
        .xbus_err_o(bc_err_o),
        .enc_key(enc_key_w),
        .dec_key(dec_key_w),
        .enc_spi(enc_spi_w),
        .enc_salt(enc_salt_w),
        .enc_seq0(enc_seq0_w),
        .dec_spi(dec_spi_w),
        .dec_salt(dec_salt_w),
        .dec_seq0(dec_seq0_w),
        .cfg_src_ip(cfg_src_ip_w),
        .cfg_dst_ip(cfg_dst_ip_w),
        .cfg_src_port(cfg_src_port_w),
        .cfg_dst_port(cfg_dst_port_w),
        .cfg_src_mac(cfg_src_mac_w),
        .cfg_dst_mac(cfg_dst_mac_w),
        .cfg_sa_en(sa_en_w),
        .cfg_cmd_start(),
        .data_sa_active(1'b0),
        .data_count_tx(32'd0),
        .data_count_rx(32'd0),
        .data_seq_out(bridge_seq_out)
    );

    assign nrv_xbus_dat_i = (nrv_xbus_adr[31:8] == 24'hF00001) ? bc_dat_o : 32'd0;
    assign nrv_xbus_ack = (nrv_xbus_adr[31:8] == 24'hF00001) ? bc_ack_o : 1'b0;
    assign nrv_xbus_err = 1'b0;

    bridge_top #(
        .MAC_TARGET("GOWIN")
    ) u_bridge (
        .clk(clk_dp),
        .rst_n(rstn),
        .gtx_clk(clk_tx),
        .gtx_clk90(clk_tx90),
        .enc_key(enc_key_w),
        .dec_key(dec_key_w),
        .enc_spi(enc_spi_w),
        .enc_salt(enc_salt_w),
        .enc_seq0(enc_seq0_w),
        .dec_spi(dec_spi_w),
        .dec_salt(dec_salt_w),
        .dec_seq0(dec_seq0_w),
        .sa_en(sa_en_w),
        .cfg_src_ip(cfg_src_ip_w),
        .cfg_dst_ip(cfg_dst_ip_w),
        .cfg_src_port(cfg_src_port_w),
        .cfg_dst_port(cfg_dst_port_w),
        .cfg_src_mac(cfg_src_mac_w),
        .cfg_dst_mac(cfg_dst_mac_w),
        .seq_out(bridge_seq_out),
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

    assign eth_rstn = 1'b1;

endmodule
