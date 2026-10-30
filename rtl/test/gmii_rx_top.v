module gmii_rx_top (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] gmii_rxd,
    input  wire       gmii_rx_dv,
    input  wire       gmii_rx_er,
    output wire [7:0] m_axis_tdata,
    output wire       m_axis_tvalid,
    output wire       m_axis_tlast,
    output wire       m_axis_tuser,
    output wire       error_bad_frame,
    output wire       error_bad_fcs
);

  axis_gmii_rx #(
      .DATA_WIDTH(8),
      .PTP_TS_ENABLE(0),
      .USER_WIDTH(1)
  ) u_rx (
      .clk(clk),
      .rst(rst),
      .gmii_rxd(gmii_rxd),
      .gmii_rx_dv(gmii_rx_dv),
      .gmii_rx_er(gmii_rx_er),
      .m_axis_tdata(m_axis_tdata),
      .m_axis_tvalid(m_axis_tvalid),
      .m_axis_tlast(m_axis_tlast),
      .m_axis_tuser(m_axis_tuser),
      .ptp_ts(96'd0),
      .clk_enable(1'b1),
      .mii_select(1'b0),
      .cfg_rx_enable(1'b1),
      .error_bad_frame(error_bad_frame),
      .error_bad_fcs(error_bad_fcs)
  );

endmodule
