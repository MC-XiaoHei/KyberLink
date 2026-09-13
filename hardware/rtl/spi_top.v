module spi_top (
    input  wire clk,
    input  wire rst_n,
    input  wire spi_sck,
    input  wire spi_mosi,
    output wire spi_miso,
    input  wire spi_csn,

    input wire        hsk_rx_wr,
    input wire [31:0] hsk_rx_data,
    input wire        hsk_rx_last,
    input wire [15:0] hsk_rx_len,

    output wire        hsk_tx_valid,
    output wire [31:0] hsk_tx_data,
    output wire        hsk_tx_last,
    output wire [15:0] hsk_tx_len,
    input  wire        hsk_tx_ready,
    output wire        hsk_rx_ready,
    output wire [ 9:0] hsk_rx_room,

    output wire         key_load,
    output wire [255:0] key_enc,
    output wire [255:0] key_dec,
    output wire [ 31:0] cfg_spi,
    output wire [ 95:0] cfg_iv,
    output wire [ 31:0] cfg_src_ip,
    output wire [ 31:0] cfg_dst_ip,
    output wire [ 15:0] cfg_src_port,
    output wire [ 15:0] cfg_dst_port,
    output wire [ 47:0] cfg_src_mac,
    output wire [ 47:0] cfg_dst_mac,
    output wire [ 31:0] cfg_seq,

    input wire        seq_upd,
    input wire [31:0] seq_val,

    input wire err_badtag_i,
    input wire err_badpad_i,
    input wire err_replay_i,
    input wire err_oversize_i,
    input wire err_rxdrop_i,

    input  wire       ctrl_ready,
    output wire       ctrl_valid,
    output wire [7:0] ctrl_data,
    output wire       ctrl_last,

    output wire soft_rst
);

  wire [ 6:0] waddr;
  wire [31:0] wdata;
  wire        wvalid;
  wire [ 6:0] raddr;
  wire        rreq;
  wire [31:0] rdata;

  spi_slave u_slave (
      .clk(clk),
      .rst_n(rst_n),
      .sck(spi_sck),
      .mosi(spi_mosi),
      .csn(spi_csn),
      .miso(spi_miso),
      .waddr(waddr),
      .wdata(wdata),
      .wvalid(wvalid),
      .raddr(raddr),
      .rreq(rreq),
      .rdata(rdata)
  );

  spi_regs u_regs (
      .clk(clk),
      .rst_n(rst_n),
      .waddr(waddr),
      .wdata(wdata),
      .wvalid(wvalid),
      .raddr(raddr),
      .rreq(rreq),
      .rdata(rdata),
      .hsk_rx_wr(hsk_rx_wr),
      .hsk_rx_data(hsk_rx_data),
      .hsk_rx_last(hsk_rx_last),
      .hsk_rx_len(hsk_rx_len),
      .hsk_tx_valid(hsk_tx_valid),
      .hsk_tx_data(hsk_tx_data),
      .hsk_tx_last(hsk_tx_last),
      .hsk_tx_len(hsk_tx_len),
      .hsk_tx_ready(hsk_tx_ready),
      .hsk_rx_ready(hsk_rx_ready),
      .hsk_rx_room(hsk_rx_room),
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
      .cfg_dst_mac(cfg_dst_mac),
      .cfg_seq(cfg_seq),
      .seq_upd(seq_upd),
      .seq_val(seq_val),
      .err_pulse({err_rxdrop_i, err_oversize_i, err_replay_i, err_badpad_i, err_badtag_i}),
      .ctrl_valid(ctrl_valid),
      .ctrl_data(ctrl_data),
      .ctrl_last(ctrl_last),
      .ctrl_ready(ctrl_ready),
      .soft_rst(soft_rst)
  );

endmodule
