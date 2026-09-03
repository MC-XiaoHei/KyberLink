module dec_min (
    input  wire clk,
    input  wire rst_n,
    input  wire [7:0] s_tdata,
    input  wire s_tvalid,
    input  wire s_tlast,
    input  wire m_tready,
    input  wire [255:0] key,
    output wire [127:0] tag_o,
    output wire tag_valid_o,
    output wire tag_ok_o
);
    wire s_tready, gcm_pt_valid, gcm_ct_valid, gcm_pt_ready, gcm_ct_ready;
    wire gcm_start, gcm_busy, gcm_done, m_tvalid, m_tlast, tag_ok;
    wire [11:0] gcm_pt_len;
    wire [95:0] gcm_nonce;
    wire [127:0] gcm_aad, gcm_ct_data, gcm_tag;
    wire [7:0] m_tdata;

    bridge_dec_path u_dec (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tvalid(s_tvalid), .s_tlast(s_tlast), .s_tready(s_tready),
        .key(key),
        .gcm_start(gcm_start), .gcm_pt_len(gcm_pt_len), .gcm_nonce(gcm_nonce), .gcm_aad(gcm_aad),
        .gcm_pt_valid(gcm_pt_valid), .gcm_pt_ready(gcm_pt_ready), .gcm_pt_data(gcm_pt_data),
        .gcm_ct_valid(gcm_ct_valid), .gcm_ct_ready(gcm_ct_ready), .gcm_ct_data(gcm_ct_data),
        .gcm_tag_valid(gcm_tag_valid), .gcm_tag(gcm_tag),
        .gcm_busy(gcm_busy), .gcm_done(gcm_done),
        .m_tdata(m_tdata), .m_tvalid(m_tvalid), .m_tlast(m_tlast), .m_tready(m_tready),
        .tag_ok(tag_ok)
    );

    gcm_stream u_gcm (
        .clk(clk), .rst_n(rst_n), .start(gcm_start), .key(key), .nonce(gcm_nonce),
        .aad(gcm_aad), .aad_len(5'd8), .pt_len(gcm_pt_len), .pt_valid(gcm_pt_valid),
        .pt_ready(gcm_pt_ready), .pt_data(gcm_pt_data), .ct_valid(gcm_ct_valid), .ct_ready(gcm_ct_ready),
        .ct_data(gcm_ct_data), .tag_valid(gcm_tag_valid), .tag(gcm_tag),
        .decrypt(1'b1), .busy(gcm_busy), .done(gcm_done), .idle()
    );
    assign tag_o = gcm_tag;
    assign tag_valid_o = gcm_tag_valid;
    assign tag_ok_o = tag_ok;
endmodule
