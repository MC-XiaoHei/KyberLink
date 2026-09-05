module dual_rgmii_top (
    input wire clk,
    input wire rst_n,
    input wire [7:0] a_lan_rxd,
    input wire a_lan_rx_dv,
    input wire a_lan_rx_last,
    output wire [7:0] a_lan_txd,
    output wire a_lan_tx_en,
    output wire a_lan_tx_last,
    input wire a_lan_tx_ready,
    input wire [7:0] b_lan_rxd,
    input wire b_lan_rx_dv,
    input wire b_lan_rx_last,
    output wire [7:0] b_lan_txd,
    output wire b_lan_tx_en,
    output wire b_lan_tx_last,
    input wire b_lan_tx_ready,
    input wire spi_a_sck,
    input wire spi_a_mosi,
    output wire spi_a_miso,
    input wire spi_a_csn,
    input wire spi_b_sck,
    input wire spi_b_mosi,
    output wire spi_b_miso,
    input wire spi_b_csn,
    output wire a_mac_rx_fcs_err,
    output wire b_mac_rx_fcs_err,
    output wire a_tag_ok,
    output wire b_tag_ok
);

  wire gtx_rst;
  assign gtx_rst = !rst_n;

  wire [7:0] a_txd;
  wire a_tx_en;
  wire a_tx_last;
  wire a_tx_ready;
  wire [7:0] a_rxd;
  wire a_rx_dv;
  wire a_rx_last;
  wire [7:0] b_txd;
  wire b_tx_en;
  wire b_tx_last;
  wire b_tx_ready;
  wire [7:0] b_rxd;
  wire b_rx_dv;
  wire b_rx_last;

  full_top u_a_full (
      .clk(clk), .rst_n(rst_n), .led(),
      .lan_rxd(a_lan_rxd), .lan_rx_dv(a_lan_rx_dv), .lan_rx_last(a_lan_rx_last),
      .lan_txd(a_lan_txd), .lan_tx_en(a_lan_tx_en), .lan_tx_last(a_lan_tx_last),
      .lan_tx_ready(a_lan_tx_ready),
      .wan_rxd(a_rxd), .wan_rx_dv(a_rx_dv), .wan_rx_last(a_rx_last),
      .wan_txd(a_txd), .wan_tx_en(a_tx_en), .wan_tx_last(a_tx_last),
      .wan_tx_ready(a_tx_ready),
      .spi_sck(spi_a_sck), .spi_mosi(spi_a_mosi), .spi_miso(spi_a_miso), .spi_csn(spi_a_csn),
      .tag_ok(a_tag_ok)
  );

  full_top u_b_full (
      .clk(clk), .rst_n(rst_n), .led(),
      .lan_rxd(b_lan_rxd), .lan_rx_dv(b_lan_rx_dv), .lan_rx_last(b_lan_rx_last),
      .lan_txd(b_lan_txd), .lan_tx_en(b_lan_tx_en), .lan_tx_last(b_lan_tx_last),
      .lan_tx_ready(b_lan_tx_ready),
      .wan_rxd(b_rxd), .wan_rx_dv(b_rx_dv), .wan_rx_last(b_rx_last),
      .wan_txd(b_txd), .wan_tx_en(b_tx_en), .wan_tx_last(b_tx_last),
      .wan_tx_ready(b_tx_ready),
      .spi_sck(spi_b_sck), .spi_mosi(spi_b_mosi), .spi_miso(spi_b_miso), .spi_csn(spi_b_csn),
      .tag_ok(b_tag_ok)
  );

  wire a_rgmii_tx_clk;
  wire [3:0] a_rgmii_txd;
  wire a_rgmii_tx_ctl;
  wire b_rgmii_tx_clk;
  wire [3:0] b_rgmii_txd;
  wire b_rgmii_tx_ctl;
  wire a_rx_fcs_err;
  wire b_rx_fcs_err;

  eth_mac_1g_rgmii #(
      .TARGET("GENERIC"), .IODDR_STYLE("IODDR2"), .USE_CLK90("FALSE"),
      .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64), .SPEED_FORCE(1'b1)
  ) u_a_phy (
      .gtx_clk(clk), .gtx_clk90(clk), .gtx_rst(gtx_rst),
      .tx_axis_tdata(a_txd), .tx_axis_tvalid(a_tx_en), .tx_axis_tready(a_tx_ready),
      .tx_axis_tlast(a_tx_last), .tx_axis_tuser(1'b0),
      .rx_axis_tdata(a_rxd), .rx_axis_tvalid(a_rx_dv), 
      .rx_axis_tlast(a_rx_last), .rx_axis_tuser(),
      .rgmii_rx_clk(b_rgmii_tx_clk), .rgmii_rxd(b_rgmii_txd), .rgmii_rx_ctl(b_rgmii_tx_ctl),
      .rgmii_tx_clk(a_rgmii_tx_clk), .rgmii_txd(a_rgmii_txd), .rgmii_tx_ctl(a_rgmii_tx_ctl),
      .tx_error_underflow(),
      .rx_error_bad_frame(), .rx_error_bad_fcs(a_rx_fcs_err),
      .speed(),
      .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
  );

  eth_mac_1g_rgmii #(
      .TARGET("GENERIC"), .IODDR_STYLE("IODDR2"), .USE_CLK90("FALSE"),
      .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64), .SPEED_FORCE(1'b1)
  ) u_b_phy (
      .gtx_clk(clk), .gtx_clk90(clk), .gtx_rst(gtx_rst),
      .tx_axis_tdata(b_txd), .tx_axis_tvalid(b_tx_en), .tx_axis_tready(b_tx_ready),
      .tx_axis_tlast(b_tx_last), .tx_axis_tuser(1'b0),
      .rx_axis_tdata(b_rxd), .rx_axis_tvalid(b_rx_dv), 
      .rx_axis_tlast(b_rx_last), .rx_axis_tuser(),
      .rgmii_rx_clk(a_rgmii_tx_clk), .rgmii_rxd(a_rgmii_txd), .rgmii_rx_ctl(a_rgmii_tx_ctl),
      .rgmii_tx_clk(b_rgmii_tx_clk), .rgmii_txd(b_rgmii_txd), .rgmii_tx_ctl(b_rgmii_tx_ctl),
      .tx_error_underflow(),
      .rx_error_bad_frame(), .rx_error_bad_fcs(b_rx_fcs_err),
      .speed(),
      .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
  );

  assign a_mac_rx_fcs_err = a_rx_fcs_err;
  assign b_mac_rx_fcs_err = b_rx_fcs_err;

endmodule
