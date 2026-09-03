module bridge_top (
    input wire clk,
    input wire rst_n,

    input  wire [7:0] s_enc_tdata,
    input  wire       s_enc_tvalid,
    input  wire       s_enc_tlast,
    output wire       s_enc_tready,
    output wire [7:0] m_enc_tdata,
    output wire       m_enc_tvalid,
    output wire       m_enc_tlast,
    input  wire       m_enc_tready,

    input  wire [7:0] s_dec_tdata,
    input  wire       s_dec_tvalid,
    input  wire       s_dec_tlast,
    output wire       s_dec_tready,
    output wire [7:0] m_dec_tdata,
    output wire       m_dec_tvalid,
    output wire       m_dec_tlast,
    input  wire       m_dec_tready,

    input  wire [255:0] key_enc,
    input  wire [255:0] key_dec,
    input  wire         key_load,
    input  wire [ 31:0] cfg_spi,
    input  wire [ 95:0] cfg_iv,
    input  wire [ 31:0] cfg_src_ip,
    input  wire [ 31:0] cfg_dst_ip,
    input  wire [ 15:0] cfg_src_port,
    input  wire [ 15:0] cfg_dst_port,
    input  wire [ 47:0] cfg_src_mac,
    input  wire [ 47:0] cfg_dst_mac,
    input  wire [ 31:0] seq_enc_in,
    output wire [ 31:0] seq_enc_out,
    output wire         tag_ok
);

  wire enc_pt_valid;
  wire enc_pt_ready;
  wire [127:0] enc_pt_data;
  wire enc_ct_valid;
  wire enc_ct_ready;
  wire [127:0] enc_ct_data;
  wire enc_tag_valid;
  wire [127:0] enc_tag;
  wire enc_busy;
  wire enc_done;

  wire dec_pt_valid;
  wire dec_pt_ready;
  wire [127:0] dec_pt_data;
  wire dec_ct_valid;
  wire dec_ct_ready;
  wire [127:0] dec_ct_data;
  wire dec_tag_valid;
  wire [127:0] dec_tag;
  wire dec_busy;
  wire dec_done;

  wire enc_start_w;
  wire [11:0] enc_len_w;
  wire [95:0] enc_nonce_w;
  wire [127:0] enc_aad_w;
  wire dec_start_w;
  wire [11:0] dec_len_w;
  wire [95:0] dec_nonce_w;
  wire [127:0] dec_aad_w;

  gcm_enc u_enc_gcm (
      .clk(clk),
      .rst_n(rst_n),
      .start(enc_start_w),
      .key(key_enc),
      .key_load(key_load),
      .nonce(enc_nonce_w),
      .aad(enc_aad_w),
      .aad_len(5'd8),
      .pt_len(enc_len_w),
      .pt_valid(enc_pt_valid),
      .pt_ready(enc_pt_ready),
      .pt_data(enc_pt_data),
      .ct_valid(enc_ct_valid),
      .ct_ready(enc_ct_ready),
      .ct_data(enc_ct_data),
      .tag_valid(enc_tag_valid),
      .tag(enc_tag),
      .busy(enc_busy),
      .done(enc_done),
      .idle()
  );

  gcm_dec u_dec_gcm (
      .clk(clk),
      .rst_n(rst_n),
      .start(dec_start_w),
      .key(key_dec),
      .key_load(key_load),
      .nonce(dec_nonce_w),
      .aad(dec_aad_w),
      .aad_len(5'd8),
      .pt_len(dec_len_w),
      .pt_valid(dec_pt_valid),
      .pt_ready(dec_pt_ready),
      .pt_data(dec_pt_data),
      .ct_valid(dec_ct_valid),
      .ct_ready(dec_ct_ready),
      .ct_data(dec_ct_data),
      .tag_valid(dec_tag_valid),
      .tag(dec_tag),
      .busy(dec_busy),
      .done(dec_done),
      .idle()
  );

  bridge_enc_path u_enc (
      .clk(clk),
      .rst_n(rst_n),
      .s_tdata(s_enc_tdata),
      .s_tvalid(s_enc_tvalid),
      .s_tlast(s_enc_tlast),
      .s_tready(s_enc_tready),
      .key(key_enc),
      .cfg_spi(cfg_spi),
      .cfg_iv(cfg_iv),
      .cfg_src_ip(cfg_src_ip),
      .cfg_dst_ip(cfg_dst_ip),
      .cfg_src_port(cfg_src_port),
      .cfg_dst_port(cfg_dst_port),
      .cfg_src_mac(cfg_src_mac),
      .cfg_dst_mac(cfg_dst_mac),
      .seq_in(seq_enc_in),
      .seq_out(seq_enc_out),
      .gcm_start(enc_start_w),
      .gcm_pt_len(enc_len_w),
      .gcm_nonce(enc_nonce_w),
      .gcm_aad(enc_aad_w),
      .gcm_pt_valid(enc_pt_valid),
      .gcm_pt_ready(enc_pt_ready),
      .gcm_pt_data(enc_pt_data),
      .gcm_ct_valid(enc_ct_valid),
      .gcm_ct_ready(enc_ct_ready),
      .gcm_ct_data(enc_ct_data),
      .gcm_tag_valid(enc_tag_valid),
      .gcm_tag(enc_tag),
      .gcm_busy(enc_busy),
      .gcm_done(enc_done),
      .m_tdata(m_enc_tdata),
      .m_tvalid(m_enc_tvalid),
      .m_tlast(m_enc_tlast),
      .m_tready(m_enc_tready)
  );

  bridge_dec_path u_dec (
      .clk(clk),
      .rst_n(rst_n),
      .s_tdata(s_dec_tdata),
      .s_tvalid(s_dec_tvalid),
      .s_tlast(s_dec_tlast),
      .s_tready(s_dec_tready),
      .key(key_dec),
      .gcm_start(dec_start_w),
      .gcm_pt_len(dec_len_w),
      .gcm_nonce(dec_nonce_w),
      .gcm_aad(dec_aad_w),
      .gcm_pt_valid(dec_pt_valid),
      .gcm_pt_ready(dec_pt_ready),
      .gcm_pt_data(dec_pt_data),
      .gcm_ct_valid(dec_ct_valid),
      .gcm_ct_ready(dec_ct_ready),
      .gcm_ct_data(dec_ct_data),
      .gcm_tag_valid(dec_tag_valid),
      .gcm_tag(dec_tag),
      .gcm_busy(dec_busy),
      .gcm_done(dec_done),
      .m_tdata(m_dec_tdata),
      .m_tvalid(m_dec_tvalid),
      .m_tlast(m_dec_tlast),
      .m_tready(m_dec_tready),
      .tag_ok(tag_ok)
  );

endmodule
