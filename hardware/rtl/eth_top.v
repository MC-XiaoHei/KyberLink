module eth_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tlast,
    output wire        s_tready,

    input  wire [47:0] cfg_src_mac,
    input  wire [47:0] cfg_dst_mac,
    input  wire [31:0] cfg_src_ip,
    input  wire [31:0] cfg_dst_ip,

    output wire [7:0]  m_data_tdata,
    output wire        m_data_tvalid,
    output wire        m_data_tlast,
    input  wire        m_data_tready,

    output wire        hsk_wr,
    output wire [31:0] hsk_data,
    output wire        hsk_last,
    output wire [15:0] hsk_len,
    input  wire        hsk_ready,

    input  wire [31:0] s_hsk_tdata,
    input  wire        s_hsk_tvalid,
    output wire        s_hsk_tready,
    input  wire [15:0] hsk_len_in,

    input  wire [7:0]  s_esp_tdata,
    input  wire        s_esp_tvalid,
    input  wire        s_esp_tlast,
    output wire        s_esp_tready,

    output wire [7:0]  m_tdata,
    output wire        m_tvalid,
    output wire        m_tlast,
    input  wire        m_tready
);

    ip_udp_eth_rx u_rx (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tlast(s_tlast), .s_tready(s_tready),
        .cfg_src_mac(cfg_src_mac),
        .m_data_tdata(m_data_tdata), .m_data_tvalid(m_data_tvalid),
        .m_data_tlast(m_data_tlast), .m_data_tready(m_data_tready),
        .hsk_wr(hsk_wr), .hsk_data(hsk_data), .hsk_last(hsk_last),
        .hsk_len(hsk_len), .hsk_ready(hsk_ready)
    );

    ip_udp_eth_tx u_tx (
        .clk(clk), .rst_n(rst_n),
        .s_esp_tdata(s_esp_tdata), .s_esp_tvalid(s_esp_tvalid),
        .s_esp_tlast(s_esp_tlast), .s_esp_tready(s_esp_tready),
        .s_hsk_tdata(s_hsk_tdata), .s_hsk_tvalid(s_hsk_tvalid),
        .s_hsk_tready(s_hsk_tready), .hsk_len(hsk_len_in),
        .cfg_src_ip(cfg_src_ip), .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac),
        .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tlast(m_tlast),
        .m_tready(m_tready)
    );

endmodule
