module spi_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        spi_sck,
    input  wire        spi_mosi,
    output wire        spi_miso,
    input  wire        spi_csn,

    input  wire        hsk_rx_wr,
    input  wire [31:0] hsk_rx_data,
    input  wire        hsk_rx_last,
    input  wire [15:0] hsk_rx_len,

    output wire        hsk_tx_valid,
    output wire [31:0] hsk_tx_data,
    output wire        hsk_tx_last,
    output wire [15:0] hsk_tx_len,
    input  wire        hsk_tx_ready,
    input  wire        hsk_tx_done,
    output wire        hsk_rx_ready,

    output wire        key_load,
    output wire [255:0] key_enc,
    output wire [255:0] key_dec,
    output wire [31:0] cfg_spi,
    output wire [95:0] cfg_iv,
    output wire [31:0] cfg_src_ip,
    output wire [31:0] cfg_dst_ip,
    output wire [15:0] cfg_src_port,
    output wire [15:0] cfg_dst_port,
    output wire [47:0] cfg_src_mac,
    output wire [47:0] cfg_dst_mac
);

    wire [6:0]  waddr;
    wire [31:0] wdata;
    wire        wvalid;
    wire [6:0]  raddr;
    wire        rreq;
    wire [31:0] rdata;

    spi_slave u_slave (
        .clk(clk), .rst_n(rst_n),
        .sck(spi_sck), .mosi(spi_mosi), .csn(spi_csn), .miso(spi_miso),
        .waddr(waddr), .wdata(wdata), .wvalid(wvalid),
        .raddr(raddr), .rreq(rreq), .rdata(rdata)
    );

    spi_regs u_regs (
        .clk(clk), .rst_n(rst_n),
        .waddr(waddr), .wdata(wdata), .wvalid(wvalid),
        .raddr(raddr), .rreq(rreq), .rdata(rdata),
        .hsk_rx_wr(hsk_rx_wr), .hsk_rx_data(hsk_rx_data),
        .hsk_rx_last(hsk_rx_last), .hsk_rx_len(hsk_rx_len),
        .hsk_tx_valid(hsk_tx_valid), .hsk_tx_data(hsk_tx_data),
        .hsk_tx_last(hsk_tx_last), .hsk_tx_len(hsk_tx_len),
        .hsk_tx_ready(hsk_tx_ready), .hsk_tx_done(hsk_tx_done),
        .hsk_rx_ready(hsk_rx_ready),
        .key_load(key_load),
        .key_enc(key_enc), .key_dec(key_dec),
        .cfg_spi(cfg_spi), .cfg_iv(cfg_iv),
        .cfg_src_ip(cfg_src_ip), .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_port(cfg_src_port), .cfg_dst_port(cfg_dst_port),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac)
    );

endmodule
