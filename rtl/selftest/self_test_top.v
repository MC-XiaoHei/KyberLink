module self_test_top (
    input wire clk,
    input wire rst_n,

    input  wire       lan_rgmii_rx_clk,
    input  wire [3:0] lan_rgmii_rxd,
    input  wire       lan_rgmii_rx_ctl,
    output wire       lan_rgmii_tx_clk,
    output wire [3:0] lan_rgmii_txd,
    output wire       lan_rgmii_tx_ctl,

    input  wire       wan_rgmii_rx_clk,
    input  wire [3:0] wan_rgmii_rxd,
    input  wire       wan_rgmii_rx_ctl,
    output wire       wan_rgmii_tx_clk,
    output wire [3:0] wan_rgmii_txd,
    output wire       wan_rgmii_tx_ctl,

    input  wire spi_sck,
    input  wire spi_mosi,
    output wire spi_miso,
    input  wire spi_csn
);

  wire clk_sys;
  wire pll_locked;

  clk_pll u_pll (
      .clk(clk),
      .clk_sys(clk_sys),
      .locked(pll_locked)
  );

  wire gtx_rst;
  assign gtx_rst = !rst_n | ~pll_locked;

  wire        enable;
  wire        loopback;
  wire        clear;

  wire [ 7:0] lan_tx_tdata;
  wire        lan_tx_tvalid;
  wire        lan_tx_tlast;
  wire        lan_tx_tready;
  wire [ 7:0] lan_rx_tdata;
  wire        lan_rx_tvalid;
  wire        lan_rx_tlast;
  wire        lan_rx_tuser;
  wire        lan_rx_tready;

  wire [ 7:0] wan_tx_tdata;
  wire        wan_tx_tvalid;
  wire        wan_tx_tlast;
  wire        wan_tx_tready;
  wire [ 7:0] wan_rx_tdata;
  wire        wan_rx_tvalid;
  wire        wan_rx_tlast;
  wire        wan_rx_tuser;
  wire        wan_rx_tready;

  wire [31:0] lan_stat_tx;
  wire [31:0] lan_stat_rx_good;
  wire [31:0] lan_stat_rx_bad;
  wire [31:0] lan_stat_rx_diff;
  wire [31:0] lan_stat_seq_tx;
  wire [31:0] lan_stat_seq_rx;

  wire [31:0] wan_stat_tx;
  wire [31:0] wan_stat_rx_good;
  wire [31:0] wan_stat_rx_bad;
  wire [31:0] wan_stat_rx_diff;
  wire [31:0] wan_stat_seq_tx;
  wire [31:0] wan_stat_seq_rx;

  wire [ 1:0] lan_speed;
  wire [ 1:0] wan_speed;
  wire        lan_rx_ovf;
  wire        wan_rx_ovf;
  wire        lan_tx_ovf;
  wire        wan_tx_ovf;
  wire        lan_tx_und;
  wire        wan_tx_und;
  wire        lan_bad_fcs;
  wire        wan_bad_fcs;

  self_test_port #(
      .LOCAL_MAC(48'h02_00_00_00_00_01),
      .PEER_MAC (48'h02_00_00_00_00_02)
  ) u_port_lan (
      .clk(clk_sys),
      .rst_n(rst_n),
      .enable(enable),
      .loopback(loopback),
      .clear(clear),
      .tx_tdata(lan_tx_tdata),
      .tx_tvalid(lan_tx_tvalid),
      .tx_tlast(lan_tx_tlast),
      .tx_tready(lan_tx_tready),
      .rx_tdata(lan_rx_tdata),
      .rx_tvalid(lan_rx_tvalid),
      .rx_tlast(lan_rx_tlast),
      .rx_tuser(lan_rx_tuser),
      .rx_tready(lan_rx_tready),
      .stat_tx(lan_stat_tx),
      .stat_rx_good(lan_stat_rx_good),
      .stat_rx_bad(lan_stat_rx_bad),
      .stat_rx_diff(lan_stat_rx_diff),
      .stat_seq_tx(lan_stat_seq_tx),
      .stat_seq_rx(lan_stat_seq_rx)
  );

  self_test_port #(
      .LOCAL_MAC(48'h02_00_00_00_00_02),
      .PEER_MAC (48'h02_00_00_00_00_01)
  ) u_port_wan (
      .clk(clk_sys),
      .rst_n(rst_n),
      .enable(enable),
      .loopback(loopback),
      .clear(clear),
      .tx_tdata(wan_tx_tdata),
      .tx_tvalid(wan_tx_tvalid),
      .tx_tlast(wan_tx_tlast),
      .tx_tready(wan_tx_tready),
      .rx_tdata(wan_rx_tdata),
      .rx_tvalid(wan_rx_tvalid),
      .rx_tlast(wan_rx_tlast),
      .rx_tuser(wan_rx_tuser),
      .rx_tready(wan_rx_tready),
      .stat_tx(wan_stat_tx),
      .stat_rx_good(wan_stat_rx_good),
      .stat_rx_bad(wan_stat_rx_bad),
      .stat_rx_diff(wan_stat_rx_diff),
      .stat_seq_tx(wan_stat_seq_tx),
      .stat_seq_rx(wan_stat_seq_rx)
  );

  self_test_regs u_regs (
      .clk(clk_sys),
      .rst_n(rst_n),
      .spi_sck(spi_sck),
      .spi_mosi(spi_mosi),
      .spi_csn(spi_csn),
      .spi_miso(spi_miso),
      .enable(enable),
      .loopback(loopback),
      .clear(clear),
      .pll_locked(pll_locked),
      .lan_stat({
        lan_stat_seq_rx,
        lan_stat_seq_tx,
        lan_stat_rx_diff,
        lan_stat_rx_bad,
        lan_stat_rx_good,
        lan_stat_tx
      }),
      .wan_stat({
        wan_stat_seq_rx,
        wan_stat_seq_tx,
        wan_stat_rx_diff,
        wan_stat_rx_bad,
        wan_stat_rx_good,
        wan_stat_tx
      }),
      .lan_speed(lan_speed),
      .wan_speed(wan_speed),
      .lan_bad_fcs(lan_bad_fcs),
      .wan_bad_fcs(wan_bad_fcs),
      .lan_rx_ovf(lan_rx_ovf),
      .lan_tx_ovf(lan_tx_ovf),
      .lan_tx_und(lan_tx_und),
      .wan_rx_ovf(wan_rx_ovf),
      .wan_tx_ovf(wan_tx_ovf),
      .wan_tx_und(wan_tx_und)
  );

  eth_mac_1g_rgmii_fifo #(
      .TARGET("GOWIN"),
      .IODDR_STYLE("IODDR"),
      .CLOCK_INPUT_STYLE("BUFG"),
      .USE_CLK90("FALSE"),
      .ENABLE_PADDING(1),
      .MIN_FRAME_LENGTH(64),
      .SPEED_FORCE(1'b0),
      .RX_FIFO_DEPTH(2048),
      .RX_FRAME_FIFO(1)
  ) u_mac_lan (
      .gtx_clk(clk_sys),
      .gtx_clk90(clk_sys),
      .gtx_rst(gtx_rst),
      .logic_clk(clk_sys),
      .logic_rst(gtx_rst),
      .tx_axis_tdata(lan_tx_tdata),
      .tx_axis_tkeep(1'b1),
      .tx_axis_tvalid(lan_tx_tvalid),
      .tx_axis_tready(lan_tx_tready),
      .tx_axis_tlast(lan_tx_tlast),
      .tx_axis_tuser(1'b0),
      .rx_axis_tdata(lan_rx_tdata),
      .rx_axis_tkeep(),
      .rx_axis_tvalid(lan_rx_tvalid),
      .rx_axis_tready(lan_rx_tready),
      .rx_axis_tlast(lan_rx_tlast),
      .rx_axis_tuser(lan_rx_tuser),
      .rgmii_rx_clk(lan_rgmii_rx_clk),
      .rgmii_rxd(lan_rgmii_rxd),
      .rgmii_rx_ctl(lan_rgmii_rx_ctl),
      .rgmii_tx_clk(lan_rgmii_tx_clk),
      .rgmii_txd(lan_rgmii_txd),
      .rgmii_tx_ctl(lan_rgmii_tx_ctl),
      .tx_error_underflow(lan_tx_und),
      .tx_fifo_overflow(lan_tx_ovf),
      .tx_fifo_bad_frame(),
      .tx_fifo_good_frame(),
      .rx_error_bad_frame(),
      .rx_error_bad_fcs(lan_bad_fcs),
      .rx_fifo_overflow(lan_rx_ovf),
      .rx_fifo_bad_frame(),
      .rx_fifo_good_frame(),
      .speed(lan_speed),
      .cfg_ifg(8'h0c),
      .cfg_tx_enable(1'b1),
      .cfg_rx_enable(1'b1)
  );

  eth_mac_1g_rgmii_fifo #(
      .TARGET("GOWIN"),
      .IODDR_STYLE("IODDR"),
      .CLOCK_INPUT_STYLE("BUFG"),
      .USE_CLK90("FALSE"),
      .ENABLE_PADDING(1),
      .MIN_FRAME_LENGTH(64),
      .SPEED_FORCE(1'b0),
      .RX_FIFO_DEPTH(2048),
      .RX_FRAME_FIFO(1)
  ) u_mac_wan (
      .gtx_clk(clk_sys),
      .gtx_clk90(clk_sys),
      .gtx_rst(gtx_rst),
      .logic_clk(clk_sys),
      .logic_rst(gtx_rst),
      .tx_axis_tdata(wan_tx_tdata),
      .tx_axis_tkeep(1'b1),
      .tx_axis_tvalid(wan_tx_tvalid),
      .tx_axis_tready(wan_tx_tready),
      .tx_axis_tlast(wan_tx_tlast),
      .tx_axis_tuser(1'b0),
      .rx_axis_tdata(wan_rx_tdata),
      .rx_axis_tkeep(),
      .rx_axis_tvalid(wan_rx_tvalid),
      .rx_axis_tready(wan_rx_tready),
      .rx_axis_tlast(wan_rx_tlast),
      .rx_axis_tuser(wan_rx_tuser),
      .rgmii_rx_clk(wan_rgmii_rx_clk),
      .rgmii_rxd(wan_rgmii_rxd),
      .rgmii_rx_ctl(wan_rgmii_rx_ctl),
      .rgmii_tx_clk(wan_rgmii_tx_clk),
      .rgmii_txd(wan_rgmii_txd),
      .rgmii_tx_ctl(wan_rgmii_tx_ctl),
      .tx_error_underflow(wan_tx_und),
      .tx_fifo_overflow(wan_tx_ovf),
      .tx_fifo_bad_frame(),
      .tx_fifo_good_frame(),
      .rx_error_bad_frame(),
      .rx_error_bad_fcs(wan_bad_fcs),
      .rx_fifo_overflow(wan_rx_ovf),
      .rx_fifo_bad_frame(),
      .rx_fifo_good_frame(),
      .speed(wan_speed),
      .cfg_ifg(8'h0c),
      .cfg_tx_enable(1'b1),
      .cfg_rx_enable(1'b1)
  );

endmodule
