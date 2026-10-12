module selftest_sim (
    input  wire clk,
    input  wire rst_n,
    input  wire spi_sck,
    input  wire spi_mosi,
    output wire spi_miso,
    input  wire spi_csn,
    input  wire corrupt
);

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
  wire        lan_rx_tready;

  wire [ 7:0] wan_tx_tdata;
  wire        wan_tx_tvalid;
  wire        wan_tx_tlast;
  wire        wan_tx_tready;
  wire [ 7:0] wan_rx_tdata;
  wire        wan_rx_tvalid;
  wire        wan_rx_tlast;
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

  assign wan_rx_tdata = lan_tx_tdata ^ {8{corrupt}};
  assign wan_rx_tvalid = lan_tx_tvalid;
  assign wan_rx_tlast = lan_tx_tlast;
  assign lan_tx_tready = 1'b1;

  assign lan_rx_tdata = wan_tx_tdata;
  assign lan_rx_tvalid = wan_tx_tvalid;
  assign lan_rx_tlast = wan_tx_tlast;
  assign wan_tx_tready = 1'b1;

  self_test_port #(
      .LOCAL_MAC(48'h02_00_00_00_00_01),
      .PEER_MAC (48'h02_00_00_00_00_02)
  ) u_port_lan (
      .clk(clk),
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
      .rx_tuser(1'b0),
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
      .clk(clk),
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
      .rx_tuser(1'b0),
      .rx_tready(wan_rx_tready),
      .stat_tx(wan_stat_tx),
      .stat_rx_good(wan_stat_rx_good),
      .stat_rx_bad(wan_stat_rx_bad),
      .stat_rx_diff(wan_stat_rx_diff),
      .stat_seq_tx(wan_stat_seq_tx),
      .stat_seq_rx(wan_stat_seq_rx)
  );

  self_test_regs u_regs (
      .clk(clk),
      .rst_n(rst_n),
      .spi_sck(spi_sck),
      .spi_mosi(spi_mosi),
      .spi_csn(spi_csn),
      .spi_miso(spi_miso),
      .enable(enable),
      .loopback(loopback),
      .clear(clear),
      .pll_locked(1'b1),
      .lan_stat({lan_stat_seq_rx, lan_stat_seq_tx, lan_stat_rx_diff, lan_stat_rx_bad, lan_stat_rx_good, lan_stat_tx}),
      .wan_stat({wan_stat_seq_rx, wan_stat_seq_tx, wan_stat_rx_diff, wan_stat_rx_bad, wan_stat_rx_good, wan_stat_tx}),
      .lan_speed(2'd0),
      .wan_speed(2'd0),
      .lan_bad_fcs(1'b0),
      .wan_bad_fcs(1'b0),
      .lan_rx_ovf(1'b0),
      .lan_tx_ovf(1'b0),
      .lan_tx_und(1'b0),
      .wan_rx_ovf(1'b0),
      .wan_tx_ovf(1'b0),
      .wan_tx_und(1'b0)
  );

endmodule
