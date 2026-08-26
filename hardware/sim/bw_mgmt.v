module bw_mgmt (
    input  wire clk,
    input  wire rst_n,
    input  wire gtx_clk,
    input  wire gtx_clk90,
    input  wire lan_rgmii_rx_clk,
    input  wire [3:0] lan_rgmii_rxd,
    input  wire lan_rgmii_rx_ctl,
    input  wire wan_rgmii_rx_clk,
    input  wire [3:0] wan_rgmii_rxd,
    input  wire wan_rgmii_rx_ctl,
    output wire lan_rgmii_tx_clk,
    output wire [3:0] lan_rgmii_txd,
    output wire lan_rgmii_tx_ctl,
    output wire [7:0] wan_tx_data,
    output wire       wan_tx_valid,
    output wire       wan_tx_last,
    input  wire       wan_tx_ready,
    input  wire [31:0] xbus_adr_i,
    input  wire [31:0] xbus_dat_i,
    input  wire        xbus_we_i,
    input  wire        xbus_stb_i,
    input  wire        xbus_cyc_i,
    output wire [31:0] xbus_dat_o,
    output wire        xbus_ack_o,
    output wire        xbus_err_o,
    input  wire        resp_wen_in,
    input  wire [12:0] resp_waddr_in,
    input  wire [7:0]  resp_wdata_in,
    input  wire        resp_done_p_in,
    input  wire [12:0] resp_len_w_in
);

    wire [255:0] enc_key = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
    wire [255:0] dec_key = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
    wire [31:0] enc_spi = 32'h84487d97;
    wire [95:0] enc_salt = 96'hcafebabefacedbaddecaf880;
    wire [31:0] enc_seq0 = 32'h11223344;
    wire [31:0] dec_spi = 32'h84487d97;
    wire [95:0] dec_salt = 96'hcafebabefacedbaddecaf880;
    wire [31:0] dec_seq0 = 0;
    wire [1:0] sa_en = 2'b11;
    wire [31:0] cfg_src_ip = 32'h0A000001;
    wire [31:0] cfg_dst_ip = 32'h0A000002;
    wire [15:0] cfg_src_port = 16'd4500;
    wire [15:0] cfg_dst_port = 16'd4500;
    wire [47:0] cfg_src_mac = 48'h020000000101;
    wire [47:0] cfg_dst_mac = 48'h020000000102;
    wire [3:0] wan_rgmii_rxd_w = wan_rgmii_rxd;
    wire wan_rgmii_rx_ctl_w = wan_rgmii_rx_ctl;
    wire wan_rgmii_rx_clk_w = wan_rgmii_rx_clk;
    wire wan_rgmii_tx_clk;
    wire [3:0] wan_rgmii_txd;
    wire wan_rgmii_tx_ctl;
    wire [31:0] seq_out;
    wire dec_tag_ok;
    wire rx_err;

    wire [7:0] lan_hs_data;
    wire lan_hs_valid, lan_hs_last, lan_hs_ready;
    wire [7:0] mgmt_tx_data;
    wire mgmt_tx_valid, mgmt_tx_last, mgmt_tx_ready;

    bridge_top u_bridge (
        .clk(clk), .rst_n(rst_n), .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90),
        .wan_rgmii_rx_clk(wan_rgmii_rx_clk), .wan_rgmii_rxd(wan_rgmii_rxd),
        .wan_rgmii_rx_ctl(wan_rgmii_rx_ctl),
        .wan_rgmii_tx_clk(wan_rgmii_tx_clk), .wan_rgmii_txd(wan_rgmii_txd),
        .wan_rgmii_tx_ctl(wan_rgmii_tx_ctl),
        .lan_rgmii_rx_clk(lan_rgmii_rx_clk), .lan_rgmii_rxd(lan_rgmii_rxd),
        .lan_rgmii_rx_ctl(lan_rgmii_rx_ctl),
        .lan_rgmii_tx_clk(lan_rgmii_tx_clk), .lan_rgmii_txd(lan_rgmii_txd),
        .lan_rgmii_tx_ctl(lan_rgmii_tx_ctl),
        .enc_key(enc_key), .dec_key(dec_key),
        .enc_spi(enc_spi), .enc_salt(enc_salt), .enc_seq0(enc_seq0),
        .dec_spi(dec_spi), .dec_salt(dec_salt), .dec_seq0(dec_seq0),
        .sa_en(sa_en),
        .cfg_src_ip(cfg_src_ip), .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_port(cfg_src_port), .cfg_dst_port(cfg_dst_port),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac),
        .seq_out(seq_out), .dec_tag_ok(dec_tag_ok), .rx_err(rx_err),
        .lan_hs_data(lan_hs_data), .lan_hs_valid(lan_hs_valid),
        .lan_hs_last(lan_hs_last), .lan_hs_ready(lan_hs_ready),
        .mgmt_tx_data(mgmt_tx_data), .mgmt_tx_valid(mgmt_tx_valid),
        .mgmt_tx_last(mgmt_tx_last), .mgmt_tx_ready(mgmt_tx_ready)
    );

    wire [7:0] req_wdata, req_rdata, resp_wdata, resp_rdata, hs_tx_rdata;
    wire req_wen, req_ren, req_done_p, req_pending, req_ack;
    wire [12:0] req_waddr, req_raddr, req_len_w, req_len_o, resp_waddr, resp_raddr, hs_tx_raddr;
    wire resp_ready, resp_clear, hs_tx_ren;
    wire [12:0] resp_len_o;
    wire [31:0] mgmt_dat_o;
    wire mgmt_ack_o, mgmt_err_o;

    hs_rx u_hs_rx (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(lan_hs_data), .s_tvalid(lan_hs_valid), .s_tlast(lan_hs_last),
        .s_tready(lan_hs_ready),
        .req_pending_nrv(req_pending),
        .req_wen(req_wen), .req_waddr(req_waddr), .req_wdata(req_wdata),
        .req_done_p(req_done_p), .req_len(req_len_w)
    );

    mgmt_buf u_mbuf (
        .clk_dp(clk), .clk_nrv(clk), .rst_n(rst_n),
        .req_wen(req_wen), .req_waddr(req_waddr), .req_wdata(req_wdata),
        .req_done_p(req_done_p), .req_len(req_len_w),
        .req_ren(req_ren), .req_raddr(req_raddr), .req_rdata(req_rdata),
        .req_pending(req_pending), .req_ack(req_ack),
        .resp_wen(resp_wen_in), .resp_waddr(resp_waddr_in), .resp_wdata(resp_wdata_in),
        .resp_len_w(resp_len_w_in), .resp_done_p(resp_done_p_in),
        .resp_ren(hs_tx_ren), .resp_raddr(hs_tx_raddr), .resp_rdata(hs_tx_rdata),
        .resp_ready(resp_ready), .resp_clear(resp_clear),
        .req_len_o(req_len_o), .resp_len_o(resp_len_o)
    );

    wire hs_tx_frame_done;

    hs_tx u_hs_tx (
        .clk(clk), .rst_n(rst_n),
        .resp_ren(hs_tx_ren), .resp_raddr(hs_tx_raddr), .resp_rdata(hs_tx_rdata),
        .resp_ready(resp_ready), .resp_len(resp_len_o), .resp_clear(resp_clear),
        .resp_frame_done(hs_tx_frame_done),
        .hdr_src_mac(cfg_src_mac), .hdr_dst_mac(cfg_dst_mac),
        .hdr_src_ip(cfg_src_ip), .hdr_dst_ip(cfg_dst_ip),
        .hdr_src_port(16'd4501), .hdr_dst_port(16'd4501),
        .m_tdata(mgmt_tx_data), .m_tvalid(mgmt_tx_valid), .m_tlast(mgmt_tx_last),
        .m_tready(mgmt_tx_ready)
    );

    mgmt_ctrl u_mgmt (
        .clk(clk), .rst_n(rst_n),
        .xbus_adr_i(xbus_adr_i), .xbus_dat_i(xbus_dat_i),
        .xbus_we_i(xbus_we_i), .xbus_stb_i(xbus_stb_i), .xbus_cyc_i(xbus_cyc_i),
        .xbus_dat_o(mgmt_dat_o), .xbus_ack_o(mgmt_ack_o), .xbus_err_o(mgmt_err_o),
        .req_ren(req_ren), .req_raddr(req_raddr), .req_rdata(req_rdata),
        .req_pending(req_pending), .req_ack(req_ack), .req_len(req_len_o),
        .resp_wen(), .resp_waddr(), .resp_wdata(),
        .resp_done_p(), .resp_len_w(), .resp_len_o(),
        .resp_ready(resp_ready), .resp_frame_done(hs_tx_frame_done)
    );

    assign xbus_dat_o = mgmt_dat_o;
    assign xbus_ack_o = mgmt_ack_o;
    assign xbus_err_o = mgmt_err_o;

    assign wan_tx_data = 8'd0;
    assign wan_tx_valid = 1'b0;
    assign wan_tx_last = 1'b0;

endmodule