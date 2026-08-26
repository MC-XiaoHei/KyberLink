`timescale 1ns/1ps
module full_top_sim #(
    parameter MGMT_TEST = 0
) (
    input  wire        clk,
    input  wire [31:0] mgmt_test_adr,
    input  wire [31:0] mgmt_test_dat,
    input  wire        mgmt_test_we,
    input  wire        mgmt_test_stb,
    input  wire        mgmt_test_cyc,
    output wire        mgmt_test_ack,
    output wire [31:0] mgmt_test_dat_o,
    input  wire        rstn,
    output wire        uart0_txd,
    input  wire        uart0_rxd,
    output wire        smc_sck,
    output wire        smc_sdo,
    output wire        smc_sdi,
    output wire        smc_csn,
    output wire        gpio_led,
    input  wire        gtx_clk,
    input  wire        gtx_clk90,
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
    wire [255:0] enc_key_w;
    wire [255:0] dec_key_w;
    wire [31:0]  enc_spi_w, enc_seq0_w, dec_spi_w, dec_seq0_w;
    wire [95:0]  enc_salt_w, dec_salt_w;
    wire [31:0]  cfg_src_ip_w, cfg_dst_ip_w;
    wire [15:0]  cfg_src_port_w, cfg_dst_port_w;
    wire [47:0]  cfg_src_mac_w, cfg_dst_mac_w;
    wire [1:0]   sa_en_w;
    wire [31:0]  bridge_seq_out;

    neorv32_full_wrapper u_nrv (
        .clk_i(clk),
        .rstn_i(rstn),
        .gpio_o(nrv_gpio),
        .uart0_txd_o(uart0_txd),
        .uart0_rxd_i(uart0_rxd),
        .smc_sck_o(smc_sck),
        .smc_sdo_o(smc_sdo),
        .smc_sdi_i(flash_sdi),
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

    wire        flash_sdi;

    w25q64_model u_flash (
        .sck(smc_sck),
        .csn(nrv_smc_csn[0]),
        .sdo(smc_sdo),
        .sdi(flash_sdi)
    );

    assign smc_sdi = flash_sdi;

    wire [31:0] bc_adr_w = MGMT_TEST ? mgmt_test_adr : nrv_xbus_adr;
    wire [31:0] bc_dat_w = MGMT_TEST ? mgmt_test_dat : nrv_xbus_dat_o;
    wire bc_we_w = MGMT_TEST ? mgmt_test_we : nrv_xbus_we;
    wire bc_stb_w = MGMT_TEST ? mgmt_test_stb : nrv_xbus_stb;
    wire bc_cyc_w = MGMT_TEST ? mgmt_test_cyc : nrv_xbus_cyc;

    bridge_ctrl u_bc (
        .clk(clk),
        .rst_n(rstn),
        .xbus_adr_i(bc_adr_w),
        .xbus_dat_i(bc_dat_w),
        .xbus_we_i(bc_we_w),
        .xbus_stb_i(bc_stb_w),
        .xbus_cyc_i(bc_cyc_w),
        .xbus_dat_o(bc_dat_o),
        .xbus_ack_o(bc_ack_o),
        .xbus_err_o(),
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

    assign nrv_xbus_dat_i = (nrv_xbus_adr[31:8] == 24'hF00001) ? bc_dat_o :
                            (nrv_xbus_adr[31:8] == 24'hF00002) ? mgmt_dat_o : 32'd0;
    assign nrv_xbus_ack = (nrv_xbus_adr[31:8] == 24'hF00001) ? bc_ack_o :
                          (nrv_xbus_adr[31:8] == 24'hF00002) ? mgmt_ack_o : 1'b0;
    assign nrv_xbus_err = (nrv_xbus_adr[31:8] == 24'hF00002) ? mgmt_err_o : 1'b0;

    bridge_top #(
        .MAC_TARGET("GOWIN")
    ) u_bridge (
        .clk(clk),
        .rst_n(rstn),
        .gtx_clk(gtx_clk),
        .gtx_clk90(gtx_clk90),
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
                .lan_hs_data(hs_rx_data), .lan_hs_valid(hs_rx_valid), .lan_hs_last(hs_rx_last),
        .lan_hs_ready(hs_rx_ready),
                .mgmt_tx_data(hs_tx_data), .mgmt_tx_valid(hs_tx_valid), .mgmt_tx_last(hs_tx_last),
        .mgmt_tx_ready(hs_tx_ready),
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

    wire [7:0]  hs_rx_data;
    wire        hs_rx_valid, hs_rx_ready, hs_rx_last;
    wire [7:0]  hs_tx_data;
    wire        hs_tx_valid, hs_tx_ready, hs_tx_last;

    wire [7:0]  req_wdata, req_rdata, resp_wdata, resp_rdata, hs_tx_rdata;
    wire        req_wen, req_ren, req_done_p, req_pending, req_ack;
    wire [12:0] req_waddr, req_raddr, req_len_w, req_len_o, resp_waddr, resp_raddr, hs_tx_raddr;
    wire        resp_wen, resp_done_p, resp_ready, resp_clear, hs_tx_ren;
    wire [12:0] resp_len_w, resp_len_o;
    wire [31:0] mgmt_dat_o;
    wire        mgmt_ack_o, mgmt_err_o;

    hs_rx u_hs_rx (
        .clk(clk), .rst_n(rstn),
        .s_tdata(hs_rx_data), .s_tvalid(hs_rx_valid), .s_tlast(hs_rx_last),
        .s_tready(hs_rx_ready),
        .req_pending_nrv(req_pending),
        .req_wen(req_wen), .req_waddr(req_waddr), .req_wdata(req_wdata),
        .req_done_p(req_done_p), .req_len(req_len_w)
    );

    mgmt_buf u_mbuf (
        .clk_dp(clk), .clk_nrv(clk), .rst_n(rstn),
        .req_wen(req_wen), .req_waddr(req_waddr), .req_wdata(req_wdata),
        .req_done_p(req_done_p), .req_len(req_len_w),
        .req_ren(req_ren), .req_raddr(req_raddr), .req_rdata(req_rdata),
        .req_pending(req_pending), .req_ack(req_ack),
        .resp_wen(resp_wen), .resp_waddr(resp_waddr), .resp_wdata(resp_wdata),
        .resp_len_w(resp_len_w), .resp_done_p(resp_done_p),
        .resp_ren(hs_tx_ren), .resp_raddr(hs_tx_raddr), .resp_rdata(hs_tx_rdata),
        .resp_ready(resp_ready), .resp_clear(resp_clear),
        .req_len_o(req_len_o), .resp_len_o(resp_len_o)
    );

    wire resp_frame_done;

    hs_tx u_hs_tx (
        .clk(clk), .rst_n(rstn),
        .resp_ren(hs_tx_ren), .resp_raddr(hs_tx_raddr), .resp_rdata(hs_tx_rdata),
        .resp_ready(resp_ready), .resp_len(resp_len_o), .resp_clear(resp_clear),
        .resp_frame_done(resp_frame_done),
        .hdr_src_mac(cfg_src_mac_w), .hdr_dst_mac(cfg_dst_mac_w),
        .hdr_src_ip(cfg_src_ip_w), .hdr_dst_ip(cfg_dst_ip_w),
        .hdr_src_port(16'd4501), .hdr_dst_port(16'd4501),
        .m_tdata(hs_tx_data), .m_tvalid(hs_tx_valid), .m_tlast(hs_tx_last),
        .m_tready(hs_tx_ready)
    );

    wire [31:0] mgmt_adr_w = MGMT_TEST ? mgmt_test_adr : nrv_xbus_adr;
    wire [31:0] mgmt_dat_w = MGMT_TEST ? mgmt_test_dat : nrv_xbus_dat_o;
    wire mgmt_we_w = MGMT_TEST ? mgmt_test_we : nrv_xbus_we;
    wire mgmt_stb_w = MGMT_TEST ? mgmt_test_stb : nrv_xbus_stb;
    wire mgmt_cyc_w = MGMT_TEST ? mgmt_test_cyc : nrv_xbus_cyc;
    assign mgmt_test_ack = MGMT_TEST ? ((mgmt_test_adr[31:8] == 24'hF00001) ? bc_ack_o :
                            (mgmt_test_adr[31:8] == 24'hF00002) ? mgmt_ack_o : 1'b0) : 1'b0;
    assign mgmt_test_dat_o = MGMT_TEST ? ((mgmt_test_adr[31:8] == 24'hF00001) ? bc_dat_o :
                             (mgmt_test_adr[31:8] == 24'hF00002) ? mgmt_dat_o : 32'd0) : 32'd0;

    mgmt_ctrl u_mgmt (
        .clk(clk), .rst_n(rstn),
        .xbus_adr_i(mgmt_adr_w), .xbus_dat_i(mgmt_dat_w),
        .xbus_we_i(mgmt_we_w), .xbus_stb_i(mgmt_stb_w), .xbus_cyc_i(mgmt_cyc_w),
        .xbus_dat_o(mgmt_dat_o), .xbus_ack_o(mgmt_ack_o), .xbus_err_o(mgmt_err_o),
        .req_ren(req_ren), .req_raddr(req_raddr), .req_rdata(req_rdata),
        .req_pending(req_pending), .req_ack(req_ack), .req_len(req_len_o),
        .resp_wen(resp_wen), .resp_waddr(resp_waddr), .resp_wdata(resp_wdata),
        .resp_done_p(resp_done_p), .resp_len_w(resp_len_w), .resp_len_o()
    ,
        .resp_ready(resp_ready), .resp_frame_done(resp_frame_done));

    assign eth_rstn = 1'b1;

endmodule
