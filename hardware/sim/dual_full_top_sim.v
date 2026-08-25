`timescale 1ns/1ps
module dual_full_top_sim (
    input  wire clk,
    input  wire gtx_clk,
    input  wire gtx_clk90,
    input  wire rstn,
    output wire uart_a_txd,
    output wire uart_b_txd,
    input  wire [31:0] a_mtest_adr,
    input  wire [31:0] a_mtest_dat,
    input  wire        a_mtest_we,
    input  wire        a_mtest_stb,
    input  wire        a_mtest_cyc,
    input  wire [31:0] b_mtest_adr,
    input  wire [31:0] b_mtest_dat,
    input  wire        b_mtest_we,
    input  wire        b_mtest_stb,
    input  wire        b_mtest_cyc,
    output wire [31:0] a_mtest_dato_o,
    output wire [31:0] b_mtest_dato_o,
    output wire a_mtest_ack_o,
    output wire b_mtest_ack_o
);
    assign a_mtest_dato_o = a_mtest_dato;
    assign b_mtest_dato_o = b_mtest_dato;
    assign a_mtest_ack_o = a_mtest_ack;
    assign b_mtest_ack_o = b_mtest_ack;

    wire [3:0] wan_txd_a, wan_rxd_a, wan_txd_b, wan_rxd_b;
    wire       wan_txctl_a, wan_rxctl_a, wan_txctl_b, wan_rxctl_b;
    wire       wan_txclk_a, wan_rxclk_a, wan_txclk_b, wan_rxclk_b;
    wire [3:0] lan_txd_a, lan_txd_b;
    wire       lan_txctl_a, lan_txctl_b;

    wire a_mtest_ack, b_mtest_ack;
    wire [31:0] a_mtest_dato, b_mtest_dato;

    full_top_sim #(.MGMT_TEST(1)) u_a (
        .clk(clk), .rstn(rstn),
        .mgmt_test_adr(a_mtest_adr), .mgmt_test_dat(a_mtest_dat),
        .mgmt_test_we(a_mtest_we), .mgmt_test_stb(a_mtest_stb), .mgmt_test_cyc(a_mtest_cyc),
        .mgmt_test_ack(a_mtest_ack), .mgmt_test_dat_o(a_mtest_dato),
        .uart0_txd(uart_a_txd), .uart0_rxd(1'b1),
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90),
        .lan_rgmii_rx_clk(1'b0), .lan_rgmii_rxd(4'd0), .lan_rgmii_rx_ctl(1'b0),
        .lan_rgmii_tx_clk(), .lan_rgmii_txd(lan_txd_a), .lan_rgmii_tx_ctl(lan_txctl_a),
        .wan_rgmii_rx_clk(wan_rxclk_a), .wan_rgmii_rxd(wan_rxd_a), .wan_rgmii_rx_ctl(wan_rxctl_a),
        .wan_rgmii_tx_clk(wan_txclk_a), .wan_rgmii_txd(wan_txd_a), .wan_rgmii_tx_ctl(wan_txctl_a)
    );

    full_top_sim #(.MGMT_TEST(1)) u_b (
        .clk(clk), .rstn(rstn),
        .mgmt_test_adr(b_mtest_adr), .mgmt_test_dat(b_mtest_dat),
        .mgmt_test_we(b_mtest_we), .mgmt_test_stb(b_mtest_stb), .mgmt_test_cyc(b_mtest_cyc),
        .mgmt_test_ack(b_mtest_ack), .mgmt_test_dat_o(b_mtest_dato),
        .uart0_txd(uart_b_txd), .uart0_rxd(1'b1),
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90),
        .lan_rgmii_rx_clk(1'b0), .lan_rgmii_rxd(4'd0), .lan_rgmii_rx_ctl(1'b0),
        .lan_rgmii_tx_clk(), .lan_rgmii_txd(lan_txd_b), .lan_rgmii_tx_ctl(lan_txctl_b),
        .wan_rgmii_rx_clk(wan_rxclk_b), .wan_rgmii_rxd(wan_rxd_b), .wan_rgmii_rx_ctl(wan_rxctl_b),
        .wan_rgmii_tx_clk(wan_txclk_b), .wan_rgmii_txd(wan_txd_b), .wan_rgmii_tx_ctl(wan_txctl_b)
    );

    assign wan_rxclk_b = wan_txclk_a;
    assign wan_rxd_b = wan_txd_a;
    assign wan_rxctl_b = wan_txctl_a;
    assign wan_rxclk_a = wan_txclk_b;
    assign wan_rxd_a = wan_txd_b;
    assign wan_rxctl_a = wan_txctl_b;

endmodule
