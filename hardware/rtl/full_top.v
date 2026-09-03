module full_top (
    input  wire clk,
    input  wire rst_n,
    output wire led,

    input  wire [7:0] lan_rxd,
    input  wire       lan_rx_dv,
    input  wire       lan_rx_last,
    output wire [7:0] lan_txd,
    output wire       lan_tx_en,
    output wire       lan_tx_last,
    input  wire       lan_tx_ready,

    input  wire [7:0] wan_rxd,
    input  wire       wan_rx_dv,
    input  wire       wan_rx_last,
    output wire [7:0] wan_txd,
    output wire       wan_tx_en,
    output wire       wan_tx_last,
    input  wire       wan_tx_ready,

    input  wire spi_sck,
    input  wire spi_mosi,
    output wire spi_miso,
    input  wire spi_csn
);

  wire key_load;
  wire [255:0] key_enc;
  wire [255:0] key_dec;
  wire [31:0] cfg_spi;
  wire [95:0] cfg_iv;
  wire [31:0] cfg_src_ip;
  wire [31:0] cfg_dst_ip;
  wire [15:0] cfg_src_port;
  wire [15:0] cfg_dst_port;
  wire [47:0] cfg_src_mac;
  wire [47:0] cfg_dst_mac;

  wire enc_s_tready;
  wire [7:0] enc_m_tdata;
  wire enc_m_tvalid;
  wire enc_m_tlast;
  wire enc_m_tready;

  wire [7:0] dec_s_tdata;
  wire dec_s_tvalid;
  wire dec_s_tlast;
  wire dec_s_tready;
  wire [7:0] dec_m_tdata;
  wire dec_m_tvalid;
  wire dec_m_tlast;
  wire dec_m_tready;

  wire hsk_wr;
  wire [31:0] hsk_data;
  wire hsk_last;
  wire [15:0] hsk_len;
  wire hsk_ready;

  wire hsk_tx_valid;
  wire [31:0] hsk_tx_data;
  wire hsk_tx_last;
  wire [15:0] hsk_tx_len;
  wire hsk_tx_ready;

  spi_top u_spi (
      .clk(clk),
      .rst_n(rst_n),
      .spi_sck(spi_sck),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .spi_csn(spi_csn),
      .hsk_rx_wr(hsk_wr),
      .hsk_rx_data(hsk_data),
      .hsk_rx_last(hsk_last),
      .hsk_rx_len(hsk_len),
      .hsk_tx_valid(hsk_tx_valid),
      .hsk_tx_data(hsk_tx_data),
      .hsk_tx_last(hsk_tx_last),
      .hsk_tx_len(hsk_tx_len),
      .hsk_tx_ready(hsk_tx_ready),
      .hsk_tx_done(wan_tx_last),
      .hsk_rx_ready(hsk_ready),
      .key_load(key_load),
      .key_enc(key_enc),
      .key_dec(key_dec),
      .cfg_spi(cfg_spi),
      .cfg_iv(cfg_iv),
      .cfg_src_ip(cfg_src_ip),
      .cfg_dst_ip(cfg_dst_ip),
      .cfg_src_port(cfg_src_port),
      .cfg_dst_port(cfg_dst_port),
      .cfg_src_mac(cfg_src_mac),
      .cfg_dst_mac(cfg_dst_mac)
  );

  bridge_top u_bridge (
      .clk(clk),
      .rst_n(rst_n),
      .s_enc_tdata(lan_rxd),
      .s_enc_tvalid(lan_rx_dv),
      .s_enc_tlast(lan_rx_last),
      .s_enc_tready(enc_s_tready),
      .key_enc(key_enc),
      .key_dec(key_dec),
      .key_load(key_load),
      .cfg_spi(cfg_spi),
      .cfg_iv(cfg_iv),
      .cfg_src_ip(cfg_src_ip),
      .cfg_dst_ip(cfg_dst_ip),
      .cfg_src_port(cfg_src_port),
      .cfg_dst_port(cfg_dst_port),
      .cfg_src_mac(cfg_src_mac),
      .cfg_dst_mac(cfg_dst_mac),
      .seq_enc_in(32'd1),
      .seq_enc_out(),
      .m_enc_tdata(enc_m_tdata),
      .m_enc_tvalid(enc_m_tvalid),
      .m_enc_tlast(enc_m_tlast),
      .m_enc_tready(enc_m_tready),
      .s_dec_tdata(dec_s_tdata),
      .s_dec_tvalid(dec_s_tvalid),
      .s_dec_tlast(dec_s_tlast),
      .s_dec_tready(dec_s_tready),
      .m_dec_tdata(dec_m_tdata),
      .m_dec_tvalid(dec_m_tvalid),
      .m_dec_tlast(dec_m_tlast),
      .m_dec_tready(dec_m_tready),
      .tag_ok()
  );

  ip_udp_eth_rx u_rx_wan (
      .clk(clk),
      .rst_n(rst_n),
      .s_tdata(wan_rxd),
      .s_tvalid(wan_rx_dv),
      .s_tlast(wan_rx_last),
      .s_tready(),
      .cfg_src_mac(cfg_src_mac),
      .m_data_tdata(dec_s_tdata),
      .m_data_tvalid(dec_s_tvalid),
      .m_data_tlast(dec_s_tlast),
      .m_data_tready(dec_s_tready),
      .hsk_wr(hsk_wr),
      .hsk_data(hsk_data),
      .hsk_last(hsk_last),
      .hsk_len(hsk_len),
      .hsk_ready(hsk_ready)
  );

  ip_udp_eth_tx u_tx_wan (
      .clk(clk),
      .rst_n(rst_n),
      .s_esp_tdata(enc_m_tdata),
      .s_esp_tvalid(enc_m_tvalid),
      .s_esp_tlast(enc_m_tlast),
      .s_esp_tready(enc_m_tready),
      .s_hsk_tdata(hsk_tx_data),
      .s_hsk_tvalid(hsk_tx_valid),
      .s_hsk_tready(hsk_tx_ready),
      .hsk_len(hsk_tx_len),
      .cfg_src_ip(cfg_src_ip),
      .cfg_dst_ip(cfg_dst_ip),
      .cfg_src_mac(cfg_src_mac),
      .cfg_dst_mac(cfg_dst_mac),
      .m_tdata(wan_txd),
      .m_tvalid(wan_tx_en),
      .m_tlast(wan_tx_last),
      .m_tready(wan_tx_ready)
  );

  assign lan_txd = dec_m_tdata;
  assign lan_tx_en = dec_m_tvalid;
  assign lan_tx_last = dec_m_tlast;
  assign dec_m_tready = lan_tx_ready;
  assign led = 1'b1;

endmodule
