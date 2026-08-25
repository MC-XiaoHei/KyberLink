module bw_enc (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,
    input  wire [255:0] key,
    input  wire [31:0]  cfg_spi,
    input  wire [95:0]  cfg_iv,
    input  wire [31:0]  seq_in,
    input  wire [31:0]  cfg_src_ip,
    input  wire [31:0]  cfg_dst_ip,
    input  wire [15:0]  cfg_src_port,
    input  wire [15:0]  cfg_dst_port,
    input  wire [47:0]  cfg_src_mac,
    input  wire [47:0]  cfg_dst_mac,
    output wire [7:0]   m_tdata,
    output wire         m_tvalid,
    output wire         m_tlast,
    input  wire         m_tready
);

    wire enc_gcm_start;
    wire [11:0] enc_gcm_pt_len;
    wire [95:0] enc_gcm_nonce;
    wire [127:0] enc_gcm_aad;
    wire enc_gcm_pt_valid, enc_gcm_pt_ready;
    wire [127:0] enc_gcm_pt_data;
    wire enc_gcm_ct_valid, enc_gcm_ct_ready;
    wire [127:0] enc_gcm_ct_data;
    wire enc_gcm_tag_valid;
    wire [127:0] enc_gcm_tag;

    bridge_enc_path u_enc (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tlast(s_tlast),
        .s_tready(s_tready),
        .key(key), .cfg_spi(cfg_spi), .cfg_iv(cfg_iv),
        .cfg_src_ip(cfg_src_ip), .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_port(cfg_src_port), .cfg_dst_port(cfg_dst_port),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac),
        .seq_in(seq_in), .seq_out(), .gcm_active(),
        .gcm_grant(1'b1), .gcm_req(), .gcm_start(enc_gcm_start),
        .gcm_pt_len(enc_gcm_pt_len), .gcm_nonce(enc_gcm_nonce), .gcm_aad(enc_gcm_aad),
        .gcm_pt_valid(enc_gcm_pt_valid), .gcm_pt_ready(enc_gcm_pt_ready),
        .gcm_pt_data(enc_gcm_pt_data),
        .gcm_ct_valid(enc_gcm_ct_valid), .gcm_ct_ready(enc_gcm_ct_ready),
        .gcm_ct_data(enc_gcm_ct_data),
        .gcm_tag_valid(enc_gcm_tag_valid), .gcm_tag(enc_gcm_tag),
        .gcm_busy(), .gcm_done(),
        .m_tdata(m_tdata), .m_tvalid(m_tvalid),
        .m_tlast(m_tlast), .m_tready(m_tready)
    );

    gcm_stream u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(enc_gcm_start), .key_refresh(1'b1), .key(key), .nonce(enc_gcm_nonce),
        .aad(enc_gcm_aad), .aad_len(5'd8), .pt_len(enc_gcm_pt_len),
        .pt_valid(enc_gcm_pt_valid), .pt_ready(enc_gcm_pt_ready), .pt_data(enc_gcm_pt_data),
        .ct_valid(enc_gcm_ct_valid), .ct_ready(enc_gcm_ct_ready), .ct_data(enc_gcm_ct_data),
        .tag_valid(enc_gcm_tag_valid), .tag(enc_gcm_tag),
        .decrypt(1'b0), .tag_in(128'd0), .tag_ok(), .busy(), .done(), .idle()
    );

endmodule