module bridge_top #(
    parameter MAC_TARGET = "GOWIN"
) (
    input  wire clk,
    input  wire rst_n,
    input  wire gtx_clk,
    input  wire gtx_clk90,

    input  wire          wan_rgmii_rx_clk,
    input  wire [3:0]    wan_rgmii_rxd,
    input  wire          wan_rgmii_rx_ctl,
    output wire          wan_rgmii_tx_clk,
    output wire [3:0]    wan_rgmii_txd,
    output wire          wan_rgmii_tx_ctl,

    input  wire          lan_rgmii_rx_clk,
    input  wire [3:0]    lan_rgmii_rxd,
    input  wire          lan_rgmii_rx_ctl,
    output wire          lan_rgmii_tx_clk,
    output wire [3:0]    lan_rgmii_txd,
    output wire          lan_rgmii_tx_ctl,

    input  wire [255:0]  key,
    input  wire [31:0]   cfg_spi,
    input  wire [95:0]   cfg_iv,
    input  wire [31:0]   seq_in,
    input  wire [31:0]   cfg_src_ip,
    input  wire [31:0]   cfg_dst_ip,
    input  wire [15:0]   cfg_src_port,
    input  wire [15:0]   cfg_dst_port,
    input  wire [47:0]   cfg_src_mac,
    input  wire [47:0]   cfg_dst_mac,

    output wire [31:0]   seq_out,
    output wire          dec_tag_ok,
    output wire          rx_err
);

    wire logic_rst = ~rst_n;

    wire [7:0] wan_tx_data, wan_rx_data;
    wire       wan_tx_valid, wan_tx_ready, wan_tx_last;
    wire       wan_rx_valid, wan_rx_ready, wan_rx_last, wan_rx_user;
    wire [7:0] lan_tx_data, lan_rx_data;
    wire       lan_tx_valid, lan_tx_ready, lan_tx_last;
    wire       lan_rx_valid, lan_rx_ready, lan_rx_last, lan_rx_user;

    wire [7:0] esp_rx_data;
    wire       esp_rx_valid, esp_rx_ready, esp_rx_last;

    wire enc_start;
    wire [11:0] enc_pt_len;
    wire [95:0] enc_nonce;
    wire [127:0] enc_aad;
    wire enc_pt_valid, enc_pt_ready;
    wire [127:0] enc_pt_data;
    wire enc_ct_valid, enc_ct_ready;
    wire [127:0] enc_ct_data;
    wire enc_tag_valid;
    wire [127:0] enc_tag;

    wire dec_start;
    wire [11:0] dec_pt_len;
    wire [95:0] dec_nonce;
    wire [127:0] dec_aad;
    wire dec_pt_valid, dec_pt_ready;
    wire [127:0] dec_pt_data;
    wire dec_ct_valid, dec_ct_ready;
    wire [127:0] dec_ct_data;
    wire dec_tag_valid;
    wire [127:0] dec_tag;
    wire dec_tag_ok_w;
    wire [127:0] dec_tag_in_w;

    gcm_stream u_gcm_enc (
        .clk(clk), .rst_n(rst_n),
        .start(enc_start), .key(key), .nonce(enc_nonce),
        .aad(enc_aad), .aad_len(5'd8), .pt_len(enc_pt_len),
        .pt_valid(enc_pt_valid), .pt_ready(enc_pt_ready), .pt_data(enc_pt_data),
        .ct_valid(enc_ct_valid), .ct_ready(enc_ct_ready), .ct_data(enc_ct_data),
        .tag_valid(enc_tag_valid), .tag(enc_tag),
        .decrypt(1'b0), .tag_in(128'd0), .tag_ok(),
        .busy(), .done()
    );

    gcm_stream u_gcm_dec (
        .clk(clk), .rst_n(rst_n),
        .start(dec_start), .key(key), .nonce(dec_nonce),
        .aad(dec_aad), .aad_len(5'd8), .pt_len(dec_pt_len),
        .pt_valid(dec_pt_valid), .pt_ready(dec_pt_ready), .pt_data(dec_pt_data),
        .ct_valid(dec_ct_valid), .ct_ready(dec_ct_ready), .ct_data(dec_ct_data),
        .tag_valid(dec_tag_valid), .tag(dec_tag),
        .decrypt(1'b1), .tag_in(dec_tag_in_w), .tag_ok(dec_tag_ok_w),
        .busy(), .done()
    );

    eth_mac_1g_rgmii_fifo #(
        .TARGET(MAC_TARGET), .IODDR_STYLE("IODDR"), .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90("TRUE"), .AXIS_DATA_WIDTH(8), .TX_FIFO_DEPTH(4096),
        .RX_FIFO_DEPTH(4096), .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)
    ) u_wan_mac (
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90), .gtx_rst(logic_rst),
        .logic_clk(clk), .logic_rst(logic_rst),
        .tx_axis_tdata(wan_tx_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(wan_tx_valid), .tx_axis_tready(wan_tx_ready),
        .tx_axis_tlast(wan_tx_last), .tx_axis_tuser(1'b0),
        .rx_axis_tdata(wan_rx_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(wan_rx_valid), .rx_axis_tready(wan_rx_ready),
        .rx_axis_tlast(wan_rx_last), .rx_axis_tuser(wan_rx_user),
        .rgmii_rx_clk(wan_rgmii_rx_clk), .rgmii_rxd(wan_rgmii_rxd),
        .rgmii_rx_ctl(wan_rgmii_rx_ctl),
        .rgmii_tx_clk(wan_rgmii_tx_clk), .rgmii_txd(wan_rgmii_txd),
        .rgmii_tx_ctl(wan_rgmii_tx_ctl),
        .tx_error_underflow(), .tx_fifo_overflow(), .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(), .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fifo_overflow(), .rx_fifo_bad_frame(), .rx_fifo_good_frame(),
        .speed(), .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );

    eth_mac_1g_rgmii_fifo #(
        .TARGET(MAC_TARGET), .IODDR_STYLE("IODDR"), .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90("TRUE"), .AXIS_DATA_WIDTH(8), .TX_FIFO_DEPTH(4096),
        .RX_FIFO_DEPTH(4096), .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)
    ) u_lan_mac (
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90), .gtx_rst(logic_rst),
        .logic_clk(clk), .logic_rst(logic_rst),
        .tx_axis_tdata(lan_tx_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(lan_tx_valid), .tx_axis_tready(lan_tx_ready),
        .tx_axis_tlast(lan_tx_last), .tx_axis_tuser(1'b0),
        .rx_axis_tdata(lan_rx_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(lan_rx_valid), .rx_axis_tready(lan_rx_ready),
        .rx_axis_tlast(lan_rx_last), .rx_axis_tuser(lan_rx_user),
        .rgmii_rx_clk(lan_rgmii_rx_clk), .rgmii_rxd(lan_rgmii_rxd),
        .rgmii_rx_ctl(lan_rgmii_rx_ctl),
        .rgmii_tx_clk(lan_rgmii_tx_clk), .rgmii_txd(lan_rgmii_txd),
        .rgmii_tx_ctl(lan_rgmii_tx_ctl),
        .tx_error_underflow(), .tx_fifo_overflow(), .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(), .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fifo_overflow(), .rx_fifo_bad_frame(), .rx_fifo_good_frame(),
        .speed(), .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );

    ip_udp_eth_rx u_decap (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(wan_rx_data), .s_tvalid(wan_rx_valid), .s_tlast(wan_rx_last),
        .s_tready(wan_rx_ready), .s_tuser(wan_rx_user),
        .cfg_dst_mac(cfg_dst_mac), .cfg_dst_port(cfg_dst_port),
        .m_tdata(esp_rx_data), .m_tvalid(esp_rx_valid), .m_tlast(esp_rx_last),
        .m_tready(esp_rx_ready)
    );

    bridge_enc_path u_enc (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(lan_rx_data), .s_tvalid(lan_rx_valid), .s_tlast(lan_rx_last),
        .s_tready(lan_rx_ready),
        .key(key), .cfg_spi(cfg_spi), .cfg_iv(cfg_iv),
        .cfg_src_ip(cfg_src_ip), .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_port(cfg_src_port), .cfg_dst_port(cfg_dst_port),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac),
        .seq_in(seq_in),
        .gcm_grant(1'b1), .gcm_req(), .gcm_start(enc_start),
        .gcm_pt_len(enc_pt_len), .gcm_nonce(enc_nonce), .gcm_aad(enc_aad),
        .gcm_pt_valid(enc_pt_valid), .gcm_pt_ready(enc_pt_ready),
        .gcm_pt_data(enc_pt_data),
        .gcm_ct_valid(enc_ct_valid), .gcm_ct_ready(enc_ct_ready),
        .gcm_ct_data(enc_ct_data),
        .gcm_tag_valid(enc_tag_valid), .gcm_tag(enc_tag),
        .gcm_busy(), .gcm_done(),
        .m_tdata(wan_tx_data), .m_tvalid(wan_tx_valid),
        .m_tlast(wan_tx_last), .m_tready(wan_tx_ready)
    );

    bridge_dec_path u_dec (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(esp_rx_data), .s_tvalid(esp_rx_valid), .s_tlast(esp_rx_last),
        .s_tready(esp_rx_ready),
        .key(key),
        .gcm_grant(1'b1), .gcm_req(), .gcm_start(dec_start),
        .gcm_pt_len(dec_pt_len), .gcm_nonce(dec_nonce), .gcm_aad(dec_aad),
        .gcm_pt_valid(dec_pt_valid), .gcm_pt_ready(dec_pt_ready),
        .gcm_pt_data(dec_pt_data),
        .gcm_ct_valid(dec_ct_valid), .gcm_ct_ready(dec_ct_ready),
        .gcm_ct_data(dec_ct_data),
        .gcm_tag_valid(dec_tag_valid), .gcm_tag(dec_tag), .gcm_tag_ok(dec_tag_ok_w),
        .gcm_busy(), .gcm_done(),
        .m_tdata(lan_tx_data), .m_tvalid(lan_tx_valid),
        .m_tlast(lan_tx_last), .m_tready(lan_tx_ready),
        .tag_ok(dec_tag_ok), .tag_in_w(dec_tag_in_w)
    );

    assign seq_out = seq_in;
    assign rx_err = wan_rx_user | lan_rx_user;

endmodule
