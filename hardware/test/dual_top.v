module dual_top (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        spi_a_sck,
    input  wire        spi_a_mosi,
    output wire        spi_a_miso,
    input  wire        spi_a_csn,

    input  wire        spi_b_sck,
    input  wire        spi_b_mosi,
    output wire        spi_b_miso,
    input  wire        spi_b_csn,

    input  wire [7:0]  a_lan_rxd,
    input  wire        a_lan_rx_dv,
    input  wire        a_lan_rx_last,
    output wire [7:0]  a_lan_txd,
    output wire        a_lan_tx_en,
    output wire        a_lan_tx_last,
    input  wire        a_lan_tx_ready,

    input  wire [7:0]  b_lan_rxd,
    input  wire        b_lan_rx_dv,
    input  wire        b_lan_rx_last,
    output wire [7:0]  b_lan_txd,
    output wire        b_lan_tx_en,
    output wire        b_lan_tx_last,
    input  wire        b_lan_tx_ready,

    output wire [7:0]  a_wan_txd_obs,
    output wire        a_wan_tx_en_obs,
    output wire [7:0]  b_wan_txd_obs,
    output wire        b_wan_tx_en_obs,
    output wire        a_mac_rx_fcs_err,
    output wire        b_mac_rx_fcs_err
);

    wire gtx_rst;

    wire a_wan_tx_ready;
    wire b_wan_tx_ready;
    wire [7:0] a_wan_rxd;
    wire a_wan_rx_dv;
    wire a_wan_rx_last;
    wire [7:0] a_wan_txd;
    wire a_wan_tx_en;
    wire a_wan_tx_last;
    wire [7:0] b_wan_rxd;
    wire b_wan_rx_dv;
    wire b_wan_rx_last;
    wire [7:0] b_wan_txd;
    wire b_wan_tx_en;
    wire b_wan_tx_last;

    wire a_rx_fcs_err;
    wire b_rx_fcs_err;

    full_top u_a_full (
        .clk(clk), .rst_n(rst_n), .led(),
        .lan_rxd(a_lan_rxd), .lan_rx_dv(a_lan_rx_dv), .lan_rx_last(a_lan_rx_last),
        .lan_txd(a_lan_txd), .lan_tx_en(a_lan_tx_en), .lan_tx_last(a_lan_tx_last),
        .lan_tx_ready(a_lan_tx_ready),
        .wan_rxd(a_wan_rxd), .wan_rx_dv(a_wan_rx_dv), .wan_rx_last(a_wan_rx_last),
        .wan_txd(a_wan_txd), .wan_tx_en(a_wan_tx_en), .wan_tx_last(a_wan_tx_last),
        .wan_tx_ready(a_wan_tx_ready),
        .spi_sck(spi_a_sck), .spi_mosi(spi_a_mosi), .spi_miso(spi_a_miso), .spi_csn(spi_a_csn)
    );

    full_top u_b_full (
        .clk(clk), .rst_n(rst_n), .led(),
        .lan_rxd(b_lan_rxd), .lan_rx_dv(b_lan_rx_dv), .lan_rx_last(b_lan_rx_last),
        .lan_txd(b_lan_txd), .lan_tx_en(b_lan_tx_en), .lan_tx_last(b_lan_tx_last),
        .lan_tx_ready(b_lan_tx_ready),
        .wan_rxd(b_wan_rxd), .wan_rx_dv(b_wan_rx_dv), .wan_rx_last(b_wan_rx_last),
        .wan_txd(b_wan_txd), .wan_tx_en(b_wan_tx_en), .wan_tx_last(b_wan_tx_last),
        .wan_tx_ready(b_wan_tx_ready),
        .spi_sck(spi_b_sck), .spi_mosi(spi_b_mosi), .spi_miso(spi_b_miso), .spi_csn(spi_b_csn)
    );

    wire [7:0] ab_gmii_txd;
    wire ab_gmii_tx_en;
    wire ab_gmii_tx_er;
    wire [7:0] ba_gmii_txd;
    wire ba_gmii_tx_en;
    wire ba_gmii_tx_er;

    wire [7:0] a_mac_tx_txd;
    wire a_mac_tx_en;
    wire a_mac_tx_last;
    wire a_mac_tx_ready;

    axis_async_fifo #(
        .DEPTH(2048), .DATA_WIDTH(8), .KEEP_ENABLE(0), .ID_ENABLE(0), .DEST_ENABLE(0), .USER_ENABLE(0)
    ) u_a_tx_fifo (
        .s_clk(clk), .s_rst(gtx_rst),
        .s_axis_tdata(a_wan_txd), .s_axis_tvalid(a_wan_tx_en), .s_axis_tready(a_wan_tx_ready),
        .s_axis_tlast(a_wan_tx_last),
        .m_clk(clk), .m_rst(gtx_rst),
        .m_axis_tdata(a_mac_tx_txd), .m_axis_tvalid(a_mac_tx_en), .m_axis_tready(a_mac_tx_ready),
        .m_axis_tlast(a_mac_tx_last)
    );

    eth_mac_1g #(
        .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)
    ) u_a_wan_phy (
        .rx_clk(clk), .rx_rst(gtx_rst), .tx_clk(clk), .tx_rst(gtx_rst),
        .tx_axis_tdata(a_mac_tx_txd), .tx_axis_tvalid(a_mac_tx_en),
        .tx_axis_tready(a_mac_tx_ready), .tx_axis_tlast(a_mac_tx_last),
        .tx_axis_tuser(1'b0),
        .rx_axis_tdata(a_wan_rxd), .rx_axis_tvalid(a_wan_rx_dv),
        .rx_axis_tlast(a_wan_rx_last), .rx_axis_tuser(),
        .gmii_rxd(ba_gmii_txd), .gmii_rx_dv(ba_gmii_tx_en), .gmii_rx_er(ba_gmii_tx_er),
        .gmii_txd(ab_gmii_txd), .gmii_tx_en(ab_gmii_tx_en), .gmii_tx_er(ab_gmii_tx_er),
        .tx_ptp_ts(96'd0), .rx_ptp_ts(96'd0),
        .tx_axis_ptp_ts(), .tx_axis_ptp_ts_tag(), .tx_axis_ptp_ts_valid(),
        .tx_lfc_req(1'b0), .tx_lfc_resend(1'b0), .rx_lfc_en(8'd0),
        .rx_lfc_req(), .rx_lfc_ack(1'b0),
        .tx_pfc_req(8'd0), .tx_pfc_resend(1'b0), .rx_pfc_en(8'd0),
        .rx_pfc_req(), .rx_pfc_ack(8'd0),
        .tx_lfc_pause_en(1'b0), .tx_pause_req(1'b0), .tx_pause_ack(),
        .rx_clk_enable(1'b1), .tx_clk_enable(1'b1),
        .rx_mii_select(1'b0), .tx_mii_select(1'b0),
        .tx_start_packet(), .tx_error_underflow(), .rx_start_packet(),
        .rx_error_bad_frame(), .rx_error_bad_fcs(a_rx_fcs_err),
        .stat_tx_mcf(), .stat_rx_mcf(),
        .stat_tx_lfc_pkt(), .stat_tx_lfc_xon(), .stat_tx_lfc_xoff(),
        .stat_tx_lfc_paused(), .stat_tx_pfc_pkt(), .stat_tx_pfc_xon(),
        .stat_tx_pfc_xoff(), .stat_tx_pfc_paused(), .stat_rx_lfc_pkt(),
        .stat_rx_lfc_xon(), .stat_rx_lfc_xoff(), .stat_rx_lfc_paused(),
        .stat_rx_pfc_pkt(), .stat_rx_pfc_xon(), .stat_rx_pfc_xoff(),
        .stat_rx_pfc_paused(),
        .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1),
        .cfg_mcf_rx_eth_dst_mcast(48'd0), .cfg_mcf_rx_check_eth_dst_mcast(1'b0),
        .cfg_mcf_rx_eth_dst_ucast(48'd0), .cfg_mcf_rx_check_eth_dst_ucast(1'b0),
        .cfg_mcf_rx_eth_src(48'd0), .cfg_mcf_rx_check_eth_src(1'b0),
        .cfg_mcf_rx_eth_type(16'd0), .cfg_mcf_rx_opcode_lfc(16'd0),
        .cfg_mcf_rx_check_opcode_lfc(1'b0), .cfg_mcf_rx_opcode_pfc(16'd0),
        .cfg_mcf_rx_check_opcode_pfc(1'b0), .cfg_mcf_rx_forward(1'b0),
        .cfg_mcf_rx_enable(1'b0), .cfg_tx_lfc_eth_dst(48'd0),
        .cfg_tx_lfc_eth_src(48'd0), .cfg_tx_lfc_eth_type(16'd0),
        .cfg_tx_lfc_opcode(16'd0), .cfg_tx_lfc_en(1'b0),
        .cfg_tx_lfc_quanta(16'd0), .cfg_tx_lfc_refresh(16'd0),
        .cfg_tx_pfc_eth_dst(48'd0), .cfg_tx_pfc_eth_src(48'd0),
        .cfg_tx_pfc_eth_type(16'd0), .cfg_tx_pfc_opcode(16'd0),
        .cfg_tx_pfc_en(1'b0), .cfg_tx_pfc_quanta(128'd0),
        .cfg_tx_pfc_refresh(128'd0), .cfg_rx_lfc_opcode(16'd0),
        .cfg_rx_lfc_en(1'b0), .cfg_rx_pfc_opcode(16'd0), .cfg_rx_pfc_en(1'b0)
    );

    wire [7:0] b_mac_tx_txd;
    wire b_mac_tx_en;
    wire b_mac_tx_last;
    wire b_mac_tx_ready;

    axis_async_fifo #(
        .DEPTH(2048), .DATA_WIDTH(8), .KEEP_ENABLE(0), .ID_ENABLE(0), .DEST_ENABLE(0), .USER_ENABLE(0)
    ) u_b_tx_fifo (
        .s_clk(clk), .s_rst(gtx_rst),
        .s_axis_tdata(b_wan_txd), .s_axis_tvalid(b_wan_tx_en), .s_axis_tready(b_wan_tx_ready),
        .s_axis_tlast(b_wan_tx_last),
        .m_clk(clk), .m_rst(gtx_rst),
        .m_axis_tdata(b_mac_tx_txd), .m_axis_tvalid(b_mac_tx_en), .m_axis_tready(b_mac_tx_ready),
        .m_axis_tlast(b_mac_tx_last)
    );

    eth_mac_1g #(
        .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64)
    ) u_b_wan_phy (
        .rx_clk(clk), .rx_rst(gtx_rst), .tx_clk(clk), .tx_rst(gtx_rst),
        .tx_axis_tdata(b_mac_tx_txd), .tx_axis_tvalid(b_mac_tx_en),
        .tx_axis_tready(b_mac_tx_ready), .tx_axis_tlast(b_mac_tx_last),
        .tx_axis_tuser(1'b0),
        .rx_axis_tdata(b_wan_rxd), .rx_axis_tvalid(b_wan_rx_dv),
        .rx_axis_tlast(b_wan_rx_last), .rx_axis_tuser(),
        .gmii_rxd(ab_gmii_txd), .gmii_rx_dv(ab_gmii_tx_en), .gmii_rx_er(ab_gmii_tx_er),
        .gmii_txd(ba_gmii_txd), .gmii_tx_en(ba_gmii_tx_en), .gmii_tx_er(ba_gmii_tx_er),
        .tx_ptp_ts(96'd0), .rx_ptp_ts(96'd0),
        .tx_axis_ptp_ts(), .tx_axis_ptp_ts_tag(), .tx_axis_ptp_ts_valid(),
        .tx_lfc_req(1'b0), .tx_lfc_resend(1'b0), .rx_lfc_en(8'd0),
        .rx_lfc_req(), .rx_lfc_ack(1'b0),
        .tx_pfc_req(8'd0), .tx_pfc_resend(1'b0), .rx_pfc_en(8'd0),
        .rx_pfc_req(), .rx_pfc_ack(8'd0),
        .tx_lfc_pause_en(1'b0), .tx_pause_req(1'b0), .tx_pause_ack(),
        .rx_clk_enable(1'b1), .tx_clk_enable(1'b1),
        .rx_mii_select(1'b0), .tx_mii_select(1'b0),
        .tx_start_packet(), .tx_error_underflow(), .rx_start_packet(),
        .rx_error_bad_frame(), .rx_error_bad_fcs(b_rx_fcs_err),
        .stat_tx_mcf(), .stat_rx_mcf(),
        .stat_tx_lfc_pkt(), .stat_tx_lfc_xon(), .stat_tx_lfc_xoff(),
        .stat_tx_lfc_paused(), .stat_tx_pfc_pkt(), .stat_tx_pfc_xon(),
        .stat_tx_pfc_xoff(), .stat_tx_pfc_paused(), .stat_rx_lfc_pkt(),
        .stat_rx_lfc_xon(), .stat_rx_lfc_xoff(), .stat_rx_lfc_paused(),
        .stat_rx_pfc_pkt(), .stat_rx_pfc_xon(), .stat_rx_pfc_xoff(),
        .stat_rx_pfc_paused(),
        .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1),
        .cfg_mcf_rx_eth_dst_mcast(48'd0), .cfg_mcf_rx_check_eth_dst_mcast(1'b0),
        .cfg_mcf_rx_eth_dst_ucast(48'd0), .cfg_mcf_rx_check_eth_dst_ucast(1'b0),
        .cfg_mcf_rx_eth_src(48'd0), .cfg_mcf_rx_check_eth_src(1'b0),
        .cfg_mcf_rx_eth_type(16'd0), .cfg_mcf_rx_opcode_lfc(16'd0),
        .cfg_mcf_rx_check_opcode_lfc(1'b0), .cfg_mcf_rx_opcode_pfc(16'd0),
        .cfg_mcf_rx_check_opcode_pfc(1'b0), .cfg_mcf_rx_forward(1'b0),
        .cfg_mcf_rx_enable(1'b0), .cfg_tx_lfc_eth_dst(48'd0),
        .cfg_tx_lfc_eth_src(48'd0), .cfg_tx_lfc_eth_type(16'd0),
        .cfg_tx_lfc_opcode(16'd0), .cfg_tx_lfc_en(1'b0),
        .cfg_tx_lfc_quanta(16'd0), .cfg_tx_lfc_refresh(16'd0),
        .cfg_tx_pfc_eth_dst(48'd0), .cfg_tx_pfc_eth_src(48'd0),
        .cfg_tx_pfc_eth_type(16'd0), .cfg_tx_pfc_opcode(16'd0),
        .cfg_tx_pfc_en(1'b0), .cfg_tx_pfc_quanta(128'd0),
        .cfg_tx_pfc_refresh(128'd0), .cfg_rx_lfc_opcode(16'd0),
        .cfg_rx_lfc_en(1'b0), .cfg_rx_pfc_opcode(16'd0), .cfg_rx_pfc_en(1'b0)
    );

    assign gtx_rst = !rst_n;
    assign a_wan_txd_obs = a_wan_txd;
    assign a_wan_tx_en_obs = a_wan_tx_en;
    assign b_wan_txd_obs = b_wan_txd;
    assign b_wan_tx_en_obs = b_wan_tx_en;
    assign a_mac_rx_fcs_err = a_rx_fcs_err;
    assign b_mac_rx_fcs_err = b_rx_fcs_err;

endmodule
