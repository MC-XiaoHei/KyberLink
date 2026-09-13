module axis_sync_fifo #(
    parameter DEPTH = 16
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,
    output wire [7:0] m_tdata,
    output wire       m_tvalid,
    output wire       m_tlast,
    input  wire       m_tready
);

  reg [8:0] mem[0:DEPTH-1];
  reg [4:0] wr_ptr, rd_ptr, cnt;

  wire wr_en = s_tvalid && s_tready;
  wire rd_en = m_tvalid && m_tready;

  assign s_tready = (cnt != DEPTH[4:0]);
  assign m_tvalid = (cnt != 5'd0);
  assign m_tdata  = mem[rd_ptr[3:0]][7:0];
  assign m_tlast  = mem[rd_ptr[3:0]][8];

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      wr_ptr <= 5'd0;
      rd_ptr <= 5'd0;
      cnt    <= 5'd0;
    end else begin
      if (wr_en) begin
        mem[wr_ptr[3:0]] <= {s_tlast, s_tdata};
        wr_ptr <= wr_ptr + 5'd1;
      end
      if (rd_en) rd_ptr <= rd_ptr + 5'd1;
      case ({
        wr_en, rd_en
      })
        2'b10:   cnt <= cnt + 5'd1;
        2'b01:   cnt <= cnt - 5'd1;
        default: cnt <= cnt;
      endcase
    end
  end

endmodule

module kyberlink_top (
    input  wire clk,
    input  wire rst_n,
    output wire led,
    output wire tag_ok,

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

  wire gtx_rst;
  assign gtx_rst = !rst_n;

  wire [7:0] lan_txd;
  wire lan_tx_en;
  wire lan_tx_last;
  wire lan_tx_ready;
  wire [7:0] lan_rxd;
  wire lan_rx_dv;
  wire lan_rx_last;

  wire [7:0] wan_txd;
  wire wan_tx_en;
  wire wan_tx_last;
  wire wan_tx_ready;
  wire [7:0] wan_rxd;
  wire wan_rx_dv;
  wire wan_rx_last;

  wire [7:0] lan_mac_txd;
  wire lan_mac_tx_en;
  wire lan_mac_tx_last;
  wire lan_tx_ready_mac;
  wire [7:0] wan_mac_txd;
  wire wan_mac_tx_en;
  wire wan_mac_tx_last;
  wire wan_tx_ready_mac;

  wire lan_rx_ready;
  wire wan_rx_ready;

  axis_sync_fifo u_fifo_lan (
      .clk(clk),
      .rst(gtx_rst),
      .s_tdata(lan_txd),
      .s_tvalid(lan_tx_en),
      .s_tlast(lan_tx_last),
      .s_tready(lan_tx_ready),
      .m_tdata(lan_mac_txd),
      .m_tvalid(lan_mac_tx_en),
      .m_tlast(lan_mac_tx_last),
      .m_tready(lan_tx_ready_mac)
  );

  axis_sync_fifo u_fifo_wan (
      .clk(clk),
      .rst(gtx_rst),
      .s_tdata(wan_txd),
      .s_tvalid(wan_tx_en),
      .s_tlast(wan_tx_last),
      .s_tready(wan_tx_ready),
      .m_tdata(wan_mac_txd),
      .m_tvalid(wan_mac_tx_en),
      .m_tlast(wan_mac_tx_last),
      .m_tready(wan_tx_ready_mac)
  );

  link_core u_core (
      .clk(clk),
      .rst_n(rst_n),
      .led(led),
      .lan_rxd(lan_rxd),
      .lan_rx_dv(lan_rx_dv),
      .lan_rx_last(lan_rx_last),
      .lan_rx_ready(lan_rx_ready),
      .lan_txd(lan_txd),
      .lan_tx_en(lan_tx_en),
      .lan_tx_last(lan_tx_last),
      .lan_tx_ready(lan_tx_ready),
      .wan_rxd(wan_rxd),
      .wan_rx_dv(wan_rx_dv),
      .wan_rx_last(wan_rx_last),
      .wan_rx_ready(wan_rx_ready),
      .wan_txd(wan_txd),
      .wan_tx_en(wan_tx_en),
      .wan_tx_last(wan_tx_last),
      .wan_tx_ready(wan_tx_ready),
      .spi_sck(spi_sck),
      .spi_mosi(spi_mosi),
      .spi_miso(spi_miso),
      .spi_csn(spi_csn),
      .tag_ok(tag_ok)
  );

  eth_mac_1g_rgmii_fifo #(
      .TARGET("GENERIC"),
      .IODDR_STYLE("IODDR2"),
      .USE_CLK90("FALSE"),
      .ENABLE_PADDING(1),
      .MIN_FRAME_LENGTH(64),
      .SPEED_FORCE(1'b1),
      .RX_FIFO_DEPTH(32),
      .TX_FIFO_DEPTH(16),
      .RX_FRAME_FIFO(0),
      .TX_FRAME_FIFO(0)
  ) u_mac_lan (
      .gtx_clk(clk),
      .gtx_clk90(clk),
      .gtx_rst(gtx_rst),
      .logic_clk(clk),
      .logic_rst(gtx_rst),
      .tx_axis_tdata(lan_mac_txd),
      .tx_axis_tkeep(1'b1),
      .tx_axis_tvalid(lan_mac_tx_en),
      .tx_axis_tready(lan_tx_ready_mac),
      .tx_axis_tlast(lan_mac_tx_last),
      .tx_axis_tuser(1'b0),
      .rx_axis_tdata(lan_rxd),
      .rx_axis_tkeep(),
      .rx_axis_tvalid(lan_rx_dv),
      .rx_axis_tready(lan_rx_ready),
      .rx_axis_tlast(lan_rx_last),
      .rx_axis_tuser(),
      .rgmii_rx_clk(lan_rgmii_rx_clk),
      .rgmii_rxd(lan_rgmii_rxd),
      .rgmii_rx_ctl(lan_rgmii_rx_ctl),
      .rgmii_tx_clk(lan_rgmii_tx_clk),
      .rgmii_txd(lan_rgmii_txd),
      .rgmii_tx_ctl(lan_rgmii_tx_ctl),
      .tx_error_underflow(),
      .tx_fifo_overflow(),
      .tx_fifo_bad_frame(),
      .tx_fifo_good_frame(),
      .rx_error_bad_frame(),
      .rx_error_bad_fcs(),
      .rx_fifo_overflow(),
      .rx_fifo_bad_frame(),
      .rx_fifo_good_frame(),
      .speed(),
      .cfg_ifg(8'h0c),
      .cfg_tx_enable(1'b1),
      .cfg_rx_enable(1'b1)
  );

  eth_mac_1g_rgmii_fifo #(
      .TARGET("GENERIC"),
      .IODDR_STYLE("IODDR2"),
      .USE_CLK90("FALSE"),
      .ENABLE_PADDING(1),
      .MIN_FRAME_LENGTH(64),
      .SPEED_FORCE(1'b1),
      .RX_FIFO_DEPTH(32),
      .TX_FIFO_DEPTH(16),
      .RX_FRAME_FIFO(0),
      .TX_FRAME_FIFO(0)
  ) u_mac_wan (
      .gtx_clk(clk),
      .gtx_clk90(clk),
      .gtx_rst(gtx_rst),
      .logic_clk(clk),
      .logic_rst(gtx_rst),
      .tx_axis_tdata(wan_mac_txd),
      .tx_axis_tkeep(1'b1),
      .tx_axis_tvalid(wan_mac_tx_en),
      .tx_axis_tready(wan_tx_ready_mac),
      .tx_axis_tlast(wan_mac_tx_last),
      .tx_axis_tuser(1'b0),
      .rx_axis_tdata(wan_rxd),
      .rx_axis_tkeep(),
      .rx_axis_tvalid(wan_rx_dv),
      .rx_axis_tready(wan_rx_ready),
      .rx_axis_tlast(wan_rx_last),
      .rx_axis_tuser(),
      .rgmii_rx_clk(wan_rgmii_rx_clk),
      .rgmii_rxd(wan_rgmii_rxd),
      .rgmii_rx_ctl(wan_rgmii_rx_ctl),
      .rgmii_tx_clk(wan_rgmii_tx_clk),
      .rgmii_txd(wan_rgmii_txd),
      .rgmii_tx_ctl(wan_rgmii_tx_ctl),
      .tx_error_underflow(),
      .tx_fifo_overflow(),
      .tx_fifo_bad_frame(),
      .tx_fifo_good_frame(),
      .rx_error_bad_frame(),
      .rx_error_bad_fcs(),
      .rx_fifo_overflow(),
      .rx_fifo_bad_frame(),
      .rx_fifo_good_frame(),
      .speed(),
      .cfg_ifg(8'h0c),
      .cfg_tx_enable(1'b1),
      .cfg_rx_enable(1'b1)
  );

endmodule
