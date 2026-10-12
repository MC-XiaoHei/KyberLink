module self_test_regs (
    input wire clk,
    input wire rst_n,

    input  wire spi_sck,
    input  wire spi_mosi,
    input  wire spi_csn,
    output wire spi_miso,

    output reg  enable,
    output reg  loopback,
    output wire clear,

    input wire pll_locked,

    input wire [191:0] lan_stat,
    input wire [191:0] wan_stat,
    input wire [  1:0] lan_speed,
    input wire [  1:0] wan_speed,
    input wire         lan_bad_fcs,
    input wire         wan_bad_fcs,
    input wire         lan_rx_ovf,
    input wire         lan_tx_ovf,
    input wire         lan_tx_und,
    input wire         wan_rx_ovf,
    input wire         wan_tx_ovf,
    input wire         wan_tx_und
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

  wire [31:0] lan_tx = lan_stat[31:0];
  wire [31:0] lan_rx_good = lan_stat[63:32];
  wire [31:0] lan_rx_bad = lan_stat[95:64];
  wire [31:0] lan_rx_diff = lan_stat[127:96];
  wire [31:0] lan_tx_seq = lan_stat[159:128];
  wire [31:0] lan_rx_seq = lan_stat[191:160];

  wire [31:0] wan_tx = wan_stat[31:0];
  wire [31:0] wan_rx_good = wan_stat[63:32];
  wire [31:0] wan_rx_bad = wan_stat[95:64];
  wire [31:0] wan_rx_diff = wan_stat[127:96];
  wire [31:0] wan_tx_seq = wan_stat[159:128];
  wire [31:0] wan_rx_seq = wan_stat[191:160];

  reg clear_r;
  assign clear = clear_r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      enable   <= 1'b0;
      loopback <= 1'b0;
      clear_r  <= 1'b0;
    end else begin
      clear_r <= wvalid && (waddr == 7'h00) && wdata[2];
      if (wvalid && (waddr == 7'h00)) begin
        enable   <= wdata[0];
        loopback <= wdata[1];
      end
    end
  end

  wire lan_fault = (lan_rx_bad != 32'd0) || (lan_rx_diff != 32'd0);
  wire wan_fault = (wan_rx_bad != 32'd0) || (wan_rx_diff != 32'd0);

  reg  lan_ovf_sticky;
  reg  lan_und_sticky;
  reg  wan_ovf_sticky;
  reg  wan_und_sticky;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lan_ovf_sticky <= 1'b0;
      lan_und_sticky <= 1'b0;
      wan_ovf_sticky <= 1'b0;
      wan_und_sticky <= 1'b0;
    end else if (clear) begin
      lan_ovf_sticky <= 1'b0;
      lan_und_sticky <= 1'b0;
      wan_ovf_sticky <= 1'b0;
      wan_und_sticky <= 1'b0;
    end else begin
      if (lan_rx_ovf || lan_tx_ovf) lan_ovf_sticky <= 1'b1;
      if (lan_tx_und) lan_und_sticky <= 1'b1;
      if (wan_rx_ovf || wan_tx_ovf) wan_ovf_sticky <= 1'b1;
      if (wan_tx_und) wan_und_sticky <= 1'b1;
    end
  end

  wire [31:0] lan_mac = {24'd0, lan_speed, lan_bad_fcs, lan_ovf_sticky, lan_und_sticky};
  wire [31:0] wan_mac = {24'd0, wan_speed, wan_bad_fcs, wan_ovf_sticky, wan_und_sticky};

  reg  [31:0] status_r;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      status_r <= 32'd0;
    end else begin
      status_r <= {27'd0, wan_fault, lan_fault, pll_locked, loopback, enable};
    end
  end

  reg [31:0] rdata_c;
  always @* begin
    rdata_c = 32'd0;
    case (raddr)
      7'h04:   rdata_c = status_r;
      7'h08:   rdata_c = lan_tx;
      7'h0c:   rdata_c = lan_rx_good;
      7'h10:   rdata_c = lan_rx_bad;
      7'h14:   rdata_c = lan_rx_diff;
      7'h18:   rdata_c = lan_tx_seq;
      7'h1c:   rdata_c = lan_rx_seq;
      7'h20:   rdata_c = wan_tx;
      7'h24:   rdata_c = wan_rx_good;
      7'h28:   rdata_c = wan_rx_bad;
      7'h2c:   rdata_c = wan_rx_diff;
      7'h30:   rdata_c = wan_tx_seq;
      7'h34:   rdata_c = wan_rx_seq;
      7'h38:   rdata_c = lan_mac;
      7'h3c:   rdata_c = wan_mac;
      default: rdata_c = 32'd0;
    endcase
  end

  assign rdata = rdata_c;

endmodule
