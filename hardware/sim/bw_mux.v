module bw_mux (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,
    input  wire [15:0] hs_dport,
    output wire [7:0] m_enc_data,
    output wire       m_enc_valid,
    output wire       m_enc_last,
    input  wire       m_enc_ready,
    output wire [7:0] m_hs_data,
    output wire       m_hs_valid,
    output wire       m_hs_last,
    input  wire       m_hs_ready
);
    lan_rx_mux u_mux (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tlast(s_tlast),
        .s_tready(s_tready),
        .hs_dport(hs_dport),
        .m_enc_data(m_enc_data), .m_enc_valid(m_enc_valid),
        .m_enc_last(m_enc_last), .m_enc_ready(m_enc_ready),
        .m_mgmt_data(), .m_mgmt_valid(), .m_mgmt_last(), .m_mgmt_ready(1'b0),
        .m_hs_data(m_hs_data), .m_hs_valid(m_hs_valid),
        .m_hs_last(m_hs_last), .m_hs_ready(m_hs_ready)
    );
endmodule