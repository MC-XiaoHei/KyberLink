module esp_mac_top #(
    parameter FRAME_BUF_DEPTH = 512,
    parameter MAC_TARGET = "GOWIN"
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          gtx_clk,
    input  wire          gtx_clk90,

    input  wire          start,
    input  wire [255:0]  key,
    input  wire [31:0]   spi,
    input  wire [31:0]   seq,
    input  wire [95:0]   iv,
    input  wire [7:0]    plaintext_len,
    input  wire [2047:0] plaintext_in,
    output wire          busy,
    output wire          done,

    output wire [2047:0] rx_plaintext_out,
    output wire [7:0]    rx_plaintext_len,
    output wire          rx_plaintext_valid,
    output wire          rx_tag_ok,
    output wire          rx_busy,
    output wire          rx_done,

    input  wire [47:0]   cfg_src_mac,
    input  wire [47:0]   cfg_dst_mac,
    input  wire [31:0]   cfg_src_ip,
    input  wire [31:0]   cfg_dst_ip,
    input  wire [15:0]   cfg_src_port,
    input  wire [15:0]   cfg_dst_port,

    input  wire          rgmii_rx_clk,
    input  wire [3:0]    rgmii_rxd,
    input  wire          rgmii_rx_ctl,
    output wire          rgmii_tx_clk,
    output wire [3:0]    rgmii_txd,
    output wire          rgmii_tx_ctl
);

    wire [7:0] esp_tdata;
    wire       esp_tvalid;
    wire       esp_tlast;
    wire       esp_tready;

    wire [7:0] m_tdata;
    wire       m_tvalid;
    wire       m_tlast;
    wire       m_tready;

    wire [7:0] rx_axis_tdata;
    wire       rx_axis_tvalid;
    wire       rx_axis_tlast;
    wire       rx_axis_tready;
    wire       rx_axis_tuser;

    wire [7:0] esp_rx_tdata;
    wire       esp_rx_tvalid;
    wire       esp_rx_tlast;
    wire       esp_rx_tready;

    wire       mac_tx_error_underflow;
    wire       mac_rx_error_bad_frame;
    wire       mac_rx_error_bad_fcs;
    wire [1:0] mac_speed;

    wire logic_rst = ~rst_n;

    esp u_esp (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .key(key),
        .spi(spi),
        .seq(seq),
        .iv(iv),
        .plaintext_len(plaintext_len),
        .plaintext_in(plaintext_in),
        .busy(busy),
        .done(done),
        .tx_data(esp_tdata),
        .tx_valid(esp_tvalid),
        .tx_last(esp_tlast),
        .tx_ready(esp_tready)
    );

    ip_udp_eth_tx #(
        .FRAME_BUF_DEPTH(FRAME_BUF_DEPTH)
    ) u_encap (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_src_mac(cfg_src_mac),
        .cfg_dst_mac(cfg_dst_mac),
        .cfg_src_ip(cfg_src_ip),
        .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_port(cfg_src_port),
        .cfg_dst_port(cfg_dst_port),
        .s_tdata(esp_tdata),
        .s_tvalid(esp_tvalid),
        .s_tlast(esp_tlast),
        .s_tready(esp_tready),
        .m_tdata(m_tdata),
        .m_tvalid(m_tvalid),
        .m_tlast(m_tlast),
        .m_tready(m_tready)
    );

    eth_mac_1g_rgmii_fifo #(
        .TARGET(MAC_TARGET),
        .IODDR_STYLE("IODDR"),
        .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90("TRUE"),
        .AXIS_DATA_WIDTH(8),
        .TX_FIFO_DEPTH(4096),
        .RX_FIFO_DEPTH(4096),
        .ENABLE_PADDING(1),
        .MIN_FRAME_LENGTH(64)
    ) u_mac (
        .gtx_clk(gtx_clk),
        .gtx_clk90(gtx_clk90),
        .gtx_rst(logic_rst),
        .logic_clk(clk),
        .logic_rst(logic_rst),
        .tx_axis_tdata(m_tdata),
        .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(m_tvalid),
        .tx_axis_tready(m_tready),
        .tx_axis_tlast(m_tlast),
        .tx_axis_tuser(1'b0),
        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tkeep(),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tready(rx_axis_tready),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(rx_axis_tuser),
        .rgmii_rx_clk(rgmii_rx_clk),
        .rgmii_rxd(rgmii_rxd),
        .rgmii_rx_ctl(rgmii_rx_ctl),
        .rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd(rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl),
        .tx_error_underflow(mac_tx_error_underflow),
        .tx_fifo_overflow(),
        .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(),
        .rx_error_bad_frame(mac_rx_error_bad_frame),
        .rx_error_bad_fcs(mac_rx_error_bad_fcs),
        .rx_fifo_overflow(),
        .rx_fifo_bad_frame(),
        .rx_fifo_good_frame(),
        .speed(mac_speed),
        .cfg_ifg(8'h0c),
        .cfg_tx_enable(1'b1),
        .cfg_rx_enable(1'b1)
    );

    ip_udp_eth_rx u_decap (
        .clk(clk),
        .rst_n(rst_n),
        .s_tdata(rx_axis_tdata),
        .s_tvalid(rx_axis_tvalid),
        .s_tlast(rx_axis_tlast),
        .s_tready(rx_axis_tready),
        .s_tuser(rx_axis_tuser),
        .cfg_dst_mac(cfg_dst_mac),
        .cfg_dst_port(cfg_dst_port),
        .m_tdata(esp_rx_tdata),
        .m_tvalid(esp_rx_tvalid),
        .m_tlast(esp_rx_tlast),
        .m_tready(esp_rx_tready)
    );

    esp_rx u_esp_rx (
        .clk(clk),
        .rst_n(rst_n),
        .s_tdata(esp_rx_tdata),
        .s_tvalid(esp_rx_tvalid),
        .s_tlast(esp_rx_tlast),
        .s_tready(esp_rx_tready),
        .key(key),
        .plaintext_out(rx_plaintext_out),
        .plaintext_len(rx_plaintext_len),
        .plaintext_valid(rx_plaintext_valid),
        .tag_ok(rx_tag_ok),
        .busy(rx_busy),
        .done(rx_done)
    );

endmodule
