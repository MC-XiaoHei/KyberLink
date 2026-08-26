module bridge_top #(
    parameter MAC_TARGET = "GOWIN"
) (
    input  wire clk,
    input  wire rst_n,
    input  wire gtx_clk,
    input  wire gtx_clk90,

    input  wire          wan_rgmii_rx_clk,
    input  wire [3:0]    wan_rgmii_rxd,
    input  wire          wan_rgmii_rx_ctl,
    output wire          wan_rgmii_tx_clk,
    output wire [3:0]    wan_rgmii_txd,
    output wire          wan_rgmii_tx_ctl,

    input  wire          lan_rgmii_rx_clk,
    input  wire [3:0]    lan_rgmii_rxd,
    input  wire          lan_rgmii_rx_ctl,
    output wire          lan_rgmii_tx_clk,
    output wire [3:0]    lan_rgmii_txd,
    output wire          lan_rgmii_tx_ctl,

    input  wire [255:0]  enc_key,
    input  wire [255:0]  dec_key,
    input  wire [31:0]   enc_spi,
    input  wire [95:0]   enc_salt,
    input  wire [31:0]   enc_seq0,
    input  wire [31:0]   dec_spi,
    input  wire [95:0]   dec_salt,
    input  wire [31:0]   dec_seq0,
    input  wire [1:0]    sa_en,
    input  wire [31:0]   cfg_src_ip,
    input  wire [31:0]   cfg_dst_ip,
    input  wire [15:0]   cfg_src_port,
    input  wire [15:0]   cfg_dst_port,
    input  wire [47:0]   cfg_src_mac,
    input  wire [47:0]   cfg_dst_mac,

    output wire [31:0]   seq_out,
    output wire          dec_tag_ok,
    output wire          rx_err

);

    wire logic_rst = ~rst_n;

    wire [7:0] wan_tx_data, wan_rx_data;
    wire       wan_tx_valid, wan_tx_ready, wan_tx_last;
    wire [7:0] enc_wan_tx_data;
    wire       enc_wan_tx_valid, enc_wan_tx_ready, enc_wan_tx_last;
    assign wan_tx_data = enc_wan_tx_data;
    assign wan_tx_valid = enc_wan_tx_valid;
    assign wan_tx_last = enc_wan_tx_last;
    assign enc_wan_tx_ready = wan_tx_ready;
    wire       wan_rx_valid, wan_rx_ready, wan_rx_last, wan_rx_user;
    wire [7:0] lan_tx_data, lan_rx_data;
    wire       lan_tx_valid, lan_tx_ready, lan_tx_last;
    wire       lan_rx_valid, lan_rx_ready, lan_rx_last, lan_rx_user;

    wire [7:0] esp_rx_data;
    wire       esp_rx_valid, esp_rx_ready, esp_rx_last;

    wire enc_start;
    wire [11:0] enc_pt_len;
    wire [95:0] enc_nonce;
    wire [127:0] enc_aad;
    wire enc_pt_valid, enc_pt_ready;
    wire [127:0] enc_pt_data;
    wire enc_ct_valid, enc_ct_ready;
    wire [127:0] enc_ct_data;

    wire dec_start;
    wire [11:0] dec_pt_len;
    wire [95:0] dec_nonce;
    wire [127:0] dec_aad;
    wire dec_pt_valid, dec_pt_ready;
    wire [127:0] dec_pt_data;
    wire dec_ct_valid, dec_ct_ready;
    wire [127:0] dec_ct_data;

    wire enc_req_w;
    wire dec_req_w;
    wire enc_grant_w;
    wire dec_grant_w;
    wire enc_active_w;
    wire dec_active_w;
    wire gcm_busy;
    wire dec_sel = dec_active_w;
    wire enc_sel = enc_active_w;
    wire gcm_pt_ready_w, gcm_ct_valid_w, gcm_tag_valid_w;
    wire [127:0] gcm_ct_data_w, gcm_tag_w;

    wire [255:0] gcm_key_w = dec_sel ? dec_key : enc_key;
    reg [255:0] key_r;
    reg         key_dirty;
    reg         gcm_busy_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_r <= 256'd0;
            key_dirty <= 1'b1;
            gcm_busy_q <= 1'b0;
        end else begin
            key_r <= gcm_key_w;
            if (gcm_key_w != key_r)
                key_dirty <= 1'b1;
            else if (gcm_busy && !gcm_busy_q)
                key_dirty <= 1'b0;
            gcm_busy_q <= gcm_busy;
        end
    end

    gcm_arb u_arb (
        .clk(clk), .rst_n(rst_n),
        .enc_req(enc_req_w), .dec_req(dec_req_w),
        .engine_busy(gcm_busy),
        .enc_grant(enc_grant_w), .dec_grant(dec_grant_w)
    );

    wire gcm_start_w    = dec_sel ? dec_start    : enc_start;
    wire [11:0] gcm_pt_len_w = dec_sel ? dec_pt_len   : enc_pt_len;
    wire [95:0] gcm_nonce_w = dec_sel ? dec_nonce   : enc_nonce;
    wire [127:0] gcm_aad_w  = dec_sel ? dec_aad    : enc_aad;
    wire gcm_pt_valid_w = dec_sel ? dec_pt_valid : enc_pt_valid;
    wire [127:0] gcm_pt_data_w = dec_sel ? dec_pt_data : enc_pt_data;
    wire gcm_ct_ready_w = dec_sel ? dec_ct_ready : enc_ct_ready;

    wire gcm_pt_ready_e  = dec_sel ? 1'b0 : gcm_pt_ready_w;
    wire gcm_pt_ready_d  = dec_sel ? gcm_pt_ready_w : 1'b0;
    wire gcm_ct_valid_e  = dec_sel ? 1'b0 : gcm_ct_valid_w;
    wire gcm_ct_valid_d  = dec_sel ? gcm_ct_valid_w : 1'b0;

    gcm_stream u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(gcm_start_w), .key_refresh(key_dirty), .key(gcm_key_w), .nonce(gcm_nonce_w),
        .aad(gcm_aad_w), .aad_len(5'd8), .pt_len(gcm_pt_len_w),
        .pt_valid(gcm_pt_valid_w), .pt_ready(gcm_pt_ready_w), .pt_data(gcm_pt_data_w),
        .ct_valid(gcm_ct_valid_w), .ct_ready(gcm_ct_ready_w), .ct_data(gcm_ct_data_w),
        .tag_valid(gcm_tag_valid_w), .tag(gcm_tag_w),
        .decrypt(dec_sel),
        .busy(gcm_busy), .done(), .idle()
    );

    eth_mac_1g_rgmii_fifo #(
        .TARGET(MAC_TARGET), .IODDR_STYLE("IODDR"), .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90("TRUE"), .AXIS_DATA_WIDTH(8), .TX_FIFO_DEPTH(512),
        .RX_FIFO_DEPTH(2048), .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64), .SPEED_FORCE(1'b1)
    ) u_wan_mac (
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90), .gtx_rst(logic_rst),
        .logic_clk(clk), .logic_rst(logic_rst),
        .tx_axis_tdata(wan_tx_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(wan_tx_valid), .tx_axis_tready(wan_tx_ready),
        .tx_axis_tlast(wan_tx_last), .tx_axis_tuser(1'b0),
        .rx_axis_tdata(wan_rx_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(wan_rx_valid), .rx_axis_tready(wan_rx_ready),
        .rx_axis_tlast(wan_rx_last), .rx_axis_tuser(wan_rx_user),
        .rgmii_rx_clk(wan_rgmii_rx_clk), .rgmii_rxd(wan_rgmii_rxd),
        .rgmii_rx_ctl(wan_rgmii_rx_ctl),
        .rgmii_tx_clk(wan_rgmii_tx_clk), .rgmii_txd(wan_rgmii_txd),
        .rgmii_tx_ctl(wan_rgmii_tx_ctl),
        .tx_error_underflow(), .tx_fifo_overflow(), .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(), .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fifo_overflow(), .rx_fifo_bad_frame(), .rx_fifo_good_frame(),
        .speed(), .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );

    eth_mac_1g_rgmii_fifo #(
        .TARGET(MAC_TARGET), .IODDR_STYLE("IODDR"), .CLOCK_INPUT_STYLE("BUFG"),
        .USE_CLK90("TRUE"), .AXIS_DATA_WIDTH(8), .TX_FIFO_DEPTH(512),
        .RX_FIFO_DEPTH(2048), .ENABLE_PADDING(1), .MIN_FRAME_LENGTH(64), .SPEED_FORCE(1'b1)
    ) u_lan_mac (
        .gtx_clk(gtx_clk), .gtx_clk90(gtx_clk90), .gtx_rst(logic_rst),
        .logic_clk(clk), .logic_rst(logic_rst),
        .tx_axis_tdata(lan_tx_data), .tx_axis_tkeep(1'b1),
        .tx_axis_tvalid(lan_tx_valid), .tx_axis_tready(lan_tx_ready),
        .tx_axis_tlast(lan_tx_last), .tx_axis_tuser(1'b0),
        .rx_axis_tdata(lan_rx_data), .rx_axis_tkeep(),
        .rx_axis_tvalid(lan_rx_valid), .rx_axis_tready(lan_rx_ready),
        .rx_axis_tlast(lan_rx_last), .rx_axis_tuser(lan_rx_user),
        .rgmii_rx_clk(lan_rgmii_rx_clk), .rgmii_rxd(lan_rgmii_rxd),
        .rgmii_rx_ctl(lan_rgmii_rx_ctl),
        .rgmii_tx_clk(lan_rgmii_tx_clk), .rgmii_txd(lan_rgmii_txd),
        .rgmii_tx_ctl(lan_rgmii_tx_ctl),
        .tx_error_underflow(), .tx_fifo_overflow(), .tx_fifo_bad_frame(),
        .tx_fifo_good_frame(), .rx_error_bad_frame(), .rx_error_bad_fcs(),
        .rx_fifo_overflow(), .rx_fifo_bad_frame(), .rx_fifo_good_frame(),
        .speed(), .cfg_ifg(8'h0c), .cfg_tx_enable(1'b1), .cfg_rx_enable(1'b1)
    );

    ip_udp_eth_rx u_decap (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(wan_rx_data), .s_tvalid(wan_rx_valid), .s_tlast(wan_rx_last),
        .s_tready(wan_rx_ready), .s_tuser(wan_rx_user),
        .cfg_dst_mac(cfg_dst_mac), .cfg_dst_port(cfg_dst_port),
        .m_tdata(esp_rx_data), .m_tvalid(esp_rx_valid), .m_tlast(esp_rx_last),
        .m_tready(esp_rx_ready)
    );

    wire [7:0] lan_p1_data;
    wire       lan_p1_valid, lan_p1_ready, lan_p1_last;
    wire [7:0] enc_lan_data;
    wire       enc_lan_valid, enc_lan_ready, enc_lan_last;
    wire [7:0] esp_p1_data;
    wire       esp_p1_valid, esp_p1_ready, esp_p1_last;

    axis_pipe1 u_lan_pipe (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(lan_rx_data), .s_tvalid(lan_rx_valid), .s_tlast(lan_rx_last),
        .s_tready(lan_rx_ready),
        .m_tdata(lan_p1_data), .m_tvalid(lan_p1_valid), .m_tlast(lan_p1_last),
        .m_tready(lan_p1_ready)
    );

    assign enc_lan_data = lan_p1_data;
    assign enc_lan_valid = lan_p1_valid;
    assign enc_lan_last = lan_p1_last;
    assign lan_p1_ready = enc_lan_ready;

    wire esp_pipe_ready;

    axis_pipe1 u_esp_pipe (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(esp_rx_data), .s_tvalid(esp_rx_valid), .s_tlast(esp_rx_last),
        .s_tready(esp_pipe_ready),
        .m_tdata(esp_p1_data), .m_tvalid(esp_p1_valid), .m_tlast(esp_p1_last),
        .m_tready(esp_p1_ready)
    );

    assign esp_rx_ready = esp_pipe_ready;

    wire enc_lan_valid_g = sa_en[0] && enc_lan_valid;
    wire esp_p1_valid_g = sa_en[1] && esp_p1_valid;

    assign enc_pt_ready  = gcm_pt_ready_e;
    assign enc_ct_valid  = gcm_ct_valid_e;
    assign dec_pt_ready  = gcm_pt_ready_d;
    assign dec_ct_valid  = gcm_ct_valid_d;

    bridge_enc_path u_enc (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(enc_lan_data), .s_tvalid(enc_lan_valid_g), .s_tlast(enc_lan_last),
        .s_tready(enc_lan_ready),
        .key(enc_key), .cfg_spi(enc_spi), .cfg_iv(enc_salt),
        .cfg_src_ip(cfg_src_ip), .cfg_dst_ip(cfg_dst_ip),
        .cfg_src_port(cfg_src_port), .cfg_dst_port(cfg_dst_port),
        .cfg_src_mac(cfg_src_mac), .cfg_dst_mac(cfg_dst_mac),
        .seq_in(enc_seq0), .seq_out(seq_out_w), .gcm_active(enc_active_w),
        .gcm_grant(enc_grant_w), .gcm_req(enc_req_w), .gcm_start(enc_start),
        .gcm_pt_len(enc_pt_len), .gcm_nonce(enc_nonce), .gcm_aad(enc_aad),
        .gcm_pt_valid(enc_pt_valid), .gcm_pt_ready(enc_pt_ready),
        .gcm_pt_data(enc_pt_data),
        .gcm_ct_valid(enc_ct_valid), .gcm_ct_ready(enc_ct_ready),
        .gcm_ct_data(gcm_ct_data_w),
        .gcm_tag_valid(gcm_tag_valid_w), .gcm_tag(gcm_tag_w),
        .gcm_busy(), .gcm_done(),
        .m_tdata(enc_wan_tx_data), .m_tvalid(enc_wan_tx_valid),
        .m_tlast(enc_wan_tx_last), .m_tready(enc_wan_tx_ready)
    );

    wire [7:0] dec_tx_data;
    wire       dec_tx_valid;
    wire       dec_tx_last;
    wire       dec_tx_ready;

    bridge_dec_path u_dec (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(esp_p1_data), .s_tvalid(esp_p1_valid_g), .s_tlast(esp_p1_last),
        .s_tready(esp_p1_ready),
        .key(dec_key),
        .gcm_grant(dec_grant_w), .gcm_req(dec_req_w), .gcm_start(dec_start),
        .gcm_pt_len(dec_pt_len), .gcm_nonce(dec_nonce), .gcm_aad(dec_aad),
        .gcm_pt_valid(dec_pt_valid), .gcm_pt_ready(dec_pt_ready),
        .gcm_pt_data(dec_pt_data),
        .gcm_ct_valid(dec_ct_valid), .gcm_ct_ready(dec_ct_ready),
        .gcm_ct_data(gcm_ct_data_w),
        .gcm_tag_valid(gcm_tag_valid_w), .gcm_tag(gcm_tag_w),
        .gcm_busy(), .gcm_done(),
        .m_tdata(dec_tx_data), .m_tvalid(dec_tx_valid), .m_tlast(dec_tx_last),
        .m_tready(dec_tx_ready),
        .tag_ok(dec_tag_ok), .gcm_active(dec_active_w)
    );

    assign lan_tx_data = dec_tx_data;
    assign lan_tx_valid = dec_tx_valid;
    assign lan_tx_last = dec_tx_last;
    assign dec_tx_ready = lan_tx_ready;

    wire seq_out_w;
    assign seq_out = seq_out_w;
    assign rx_err = wan_rx_user | lan_rx_user;

endmodule
