module bw_dec (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,
    input  wire [255:0] key,
    output wire [7:0]   m_tdata,
    output wire         m_tvalid,
    output wire         m_tlast,
    input  wire         m_tready,
    output reg          tag_ok
);

    wire dec_gcm_start;
    wire [11:0] dec_gcm_pt_len;
    wire [95:0] dec_gcm_nonce;
    wire [127:0] dec_gcm_aad;
    wire dec_gcm_pt_valid, dec_gcm_pt_ready;
    wire [127:0] dec_gcm_pt_data;
    wire dec_gcm_ct_valid, dec_gcm_ct_ready;
    wire [127:0] dec_gcm_ct_data;
    wire dec_gcm_tag_valid;
    wire [127:0] dec_gcm_tag;

    bridge_dec_path u_dec (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tlast(s_tlast),
        .s_tready(s_tready),
        .key(key),
        .gcm_grant(1'b1), .gcm_req(), .gcm_start(dec_gcm_start),
        .gcm_pt_len(dec_gcm_pt_len), .gcm_nonce(dec_gcm_nonce), .gcm_aad(dec_gcm_aad),
        .gcm_pt_valid(dec_gcm_pt_valid), .gcm_pt_ready(dec_gcm_pt_ready),
        .gcm_pt_data(dec_gcm_pt_data),
        .gcm_ct_valid(dec_gcm_ct_valid), .gcm_ct_ready(dec_gcm_ct_ready),
        .gcm_ct_data(dec_gcm_ct_data),
        .gcm_tag_valid(dec_gcm_tag_valid), .gcm_tag(dec_gcm_tag),
        .gcm_busy(), .gcm_done(),
        .m_tdata(m_tdata), .m_tvalid(m_tvalid),
        .m_tlast(m_tlast), .m_tready(m_tready),
        .tag_ok(tag_ok), .gcm_active()
    );

    gcm_stream u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(dec_gcm_start), .key_refresh(1'b1), .key(key), .nonce(dec_gcm_nonce),
        .aad(dec_gcm_aad), .aad_len(5'd8), .pt_len(dec_gcm_pt_len),
        .pt_valid(dec_gcm_pt_valid), .pt_ready(dec_gcm_pt_ready), .pt_data(dec_gcm_pt_data),
        .ct_valid(dec_gcm_ct_valid), .ct_ready(dec_gcm_ct_ready), .ct_data(dec_gcm_ct_data),
        .tag_valid(dec_gcm_tag_valid), .tag(dec_gcm_tag),
        .decrypt(1'b1),
        .busy(), .done(), .idle()
    );

endmodule