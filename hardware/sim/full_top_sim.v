// Full-system simulation top (verilator only): NEORV32 (converted Verilog)
// + bridge_ctrl (XBUS) + bridge_top (data plane). Not for PnR.
`timescale 1ns/1ps
module full_top_sim (
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
    wire [31:0] bc_dat_o;
    wire        bc_ack_o;

    neorv32_full_wrapper u_nrv (
        .clk_i(clk),
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

    bridge_ctrl u_bc (
        .clk(clk),
        .rst_n(rstn),
        .xbus_adr_i(nrv_xbus_adr),
        .xbus_dat_i(nrv_xbus_dat_o),
        .xbus_we_i(nrv_xbus_we),
        .xbus_stb_i(nrv_xbus_stb),
        .xbus_cyc_i(nrv_xbus_cyc),
        .xbus_dat_o(bc_dat_o),
        .xbus_ack_o(bc_ack_o),
        .xbus_err_o(),
        .cfg_key(),
        .cfg_sa_en(),
        .cfg_cmd_start(),
        .data_sa_active(1'b0),
        .data_count_tx(32'd0),
        .data_count_rx(32'd0)
    );

    assign nrv_xbus_dat_i = (nrv_xbus_adr[31:8] == 24'hF00001) ? bc_dat_o : 32'd0;
    assign nrv_xbus_ack = bc_ack_o;
    assign nrv_xbus_err = 1'b0;

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

    assign eth_rstn = 1'b1;

endmodule
