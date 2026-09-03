module enc_min (
    input  wire clk,
    input  wire rst_n,
    input  wire [7:0] s_tdata,
    input  wire s_tvalid,
    input  wire s_tlast,
    input  wire m_tready,
    input  wire [255:0] key,
    input  wire [31:0] cfg_spi,
    input  wire [95:0] cfg_iv,
    input  wire [31:0] cfg_src_ip,
    input  wire [31:0] cfg_dst_ip,
    input  wire [15:0] cfg_src_port,
    input  wire [15:0] cfg_dst_port,
    input  wire [47:0] cfg_src_mac,
    input  wire [47:0] cfg_dst_mac,
    input  wire [31:0] seq_in,
    output wire [127:0] tag_o,
    output wire tag_valid_o
);
    wire s_tready, gcm_pt_valid, gcm_ct_valid, gcm_pt_ready, gcm_ct_ready;
    wire gcm_start, gcm_busy, gcm_done, m_tvalid, m_tlast, seq_en;
    wire [127:0] gcm_pt_data;
    wire [11:0] gcm_pt_len;
    wire [95:0] gcm_nonce;
    wire [127:0] gcm_aad, gcm_ct_data, gcm_tag;
    wire [7:0] m_tdata;
    wire [31:0] seq_out;

    bridge_enc_path u_enc (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tlast(s_tlast), .s_tready(s_tready),
        .key(key), .cfg_spi(cfg_spi), .cfg_iv(cfg_iv),
        .cfg_src_ip(cfg_src_ip), .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_port(cfg_src_port), .cfg_dst_port(cfg_dst_port),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac),
        .seq_in(seq_in), .seq_out(seq_out),
        .gcm_start(gcm_start), .gcm_pt_len(gcm_pt_len), .gcm_nonce(gcm_nonce), .gcm_aad(gcm_aad),
        .gcm_pt_valid(gcm_pt_valid), .gcm_pt_ready(gcm_pt_ready), .gcm_pt_data(gcm_pt_data),
        .gcm_ct_valid(gcm_ct_valid), .gcm_ct_ready(gcm_ct_ready), .gcm_ct_data(gcm_ct_data),
        .gcm_tag_valid(gcm_tag_valid), .gcm_tag(gcm_tag),
        .gcm_busy(gcm_busy), .gcm_done(gcm_done),
        .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tlast(m_tlast), .m_tready(m_tready)
    );

    gcm_stream u_gcm (
        .clk(clk), .rst_n(rst_n), .start(gcm_start), .key(key), .nonce(gcm_nonce),
        .aad(gcm_aad), .aad_len(5'd8), .pt_len(gcm_pt_len), .pt_valid(gcm_pt_valid),
        .pt_ready(gcm_pt_ready), .pt_data(gcm_pt_data), .ct_valid(gcm_ct_valid), .ct_ready(gcm_ct_ready),
        .ct_data(gcm_ct_data), .tag_valid(gcm_tag_valid), .tag(gcm_tag),
        .decrypt(1'b0), .busy(gcm_busy), .done(gcm_done), .idle()
    );
    assign tag_o = gcm_tag;
    assign tag_valid_o = gcm_tag_valid;
endmodule
