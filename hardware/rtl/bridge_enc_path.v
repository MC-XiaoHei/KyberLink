module bridge_enc_path (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [7:0]    s_tdata,
    input  wire          s_tvalid,
    input  wire          s_tlast,
    output wire          s_tready,

    input  wire [255:0]  key,
    input  wire [31:0]   cfg_spi,
    input  wire [95:0]   cfg_iv,
    input  wire [31:0]   cfg_src_ip,
    input  wire [31:0]   cfg_dst_ip,
    input  wire [15:0]   cfg_src_port,
    input  wire [15:0]   cfg_dst_port,
    input  wire [47:0]   cfg_src_mac,
    input  wire [47:0]   cfg_dst_mac,
    input  wire [31:0]   seq_in,

    input  wire          gcm_grant,
    output reg           gcm_req,
    output reg           gcm_start,
    output reg  [11:0]   gcm_pt_len,
    output reg  [95:0]   gcm_nonce,
    output reg  [127:0]  gcm_aad,
    output reg           gcm_pt_valid,
    input  wire          gcm_pt_ready,
    output reg  [127:0]  gcm_pt_data,
    input  wire          gcm_ct_valid,
    output reg           gcm_ct_ready,
    input  wire [127:0]  gcm_ct_data,
    input  wire          gcm_tag_valid,
    input  wire [127:0]  gcm_tag,
    input  wire          gcm_busy,
    input  wire          gcm_done,

    output wire [7:0]    m_tdata,
    output wire          m_tvalid,
    output wire          m_tlast,
    input  wire          m_tready
);

    localparam ST_IDLE = 2'd0;
    localparam ST_RX   = 2'd1;
    localparam ST_ENC  = 2'd2;
    localparam ST_TX   = 2'd3;

    reg [1:0] state;

    (* syn_ramstyle = "block" *) reg [127:0] frm_buf [0:127];
    (* syn_ramstyle = "block" *) reg [127:0] ct_buf [0:127];
    reg [127:0] blk_acc;
    reg [11:0]  fcnt;
    reg [11:0]  frm_len;
    reg [7:0]   pt_idx;
    reg [7:0]   pt_rd_addr;
    reg [127:0] pt_rd_data;
    reg         pt_req;
    reg         pt_data_v;
    reg         grant_used;
    reg [7:0]   ct_idx;
    reg [15:0]  tx_cnt;
    reg [127:0] tag_r;
    reg [31:0]  seq_r;
    reg [15:0]  ip_csum_r;
    reg [127:0] tx_blk;
    reg [3:0]   tx_b;
    reg         tx_blk_v;
    reg [7:0]   ct_rd_idx;
    reg [127:0] ct_rd_data;

    wire [15:0] udp_len = 16'd46 + {4'd0, frm_len};
    wire [15:0] total_len = 16'd66 + {4'd0, frm_len};
    wire [15:0] frame_n = 16'd80 + {4'd0, frm_len};
    wire [15:0] ct_end = 16'd62 + {4'd0, frm_len};
    wire [8:0]  nct = {1'b0, frm_len[11:4]} + {8'd0, |frm_len[3:0]};

    function [15:0] fold16(input [31:0] s);
        begin
            fold16 = s[15:0] + s[31:16];
        end
    endfunction

    wire [15:0] ip_sum = 16'h4500 + total_len + 16'h4000 + 16'h4011
                       + cfg_src_ip[31:16] + cfg_src_ip[15:0]
                       + cfg_dst_ip[31:16] + cfg_dst_ip[15:0];
    wire [15:0] ip_csum_c = ~fold16({16'd0, ip_sum});

    assign s_tready = (state == ST_IDLE) || (state == ST_RX);

    always @(posedge clk) begin
        pt_rd_data <= frm_buf[pt_rd_addr];
    end
    always @(posedge clk) begin
        ct_rd_data <= ct_buf[ct_rd_idx];
    end

    function [7:0] hdr_byte(input [15:0] o);
        reg [15:0] ipd;
        begin
            if (o < 16'd6)
                hdr_byte = cfg_dst_mac[47 - 8*o[2:0] -: 8];
            else if (o < 16'd12)
                hdr_byte = cfg_src_mac[47 - 8*(o - 16'd6) -: 8];
            else if (o < 16'd14)
                hdr_byte = (o == 16'd12) ? 8'h08 : 8'h00;
            else if (o < 16'd34) begin
                ipd = o - 16'd14;
                case (ipd[4:0])
                    5'd0: hdr_byte = 8'h45;
                    5'd1: hdr_byte = 8'h00;
                    5'd2: hdr_byte = total_len[15:8];
                    5'd3: hdr_byte = total_len[7:0];
                    5'd4: hdr_byte = 8'h00;
                    5'd5: hdr_byte = 8'h00;
                    5'd6: hdr_byte = 8'h40;
                    5'd7: hdr_byte = 8'h00;
                    5'd8: hdr_byte = 8'h40;
                    5'd9: hdr_byte = 8'h11;
                    5'd10: hdr_byte = ip_csum_r[15:8];
                    5'd11: hdr_byte = ip_csum_r[7:0];
                    5'd12: hdr_byte = cfg_src_ip[31:24];
                    5'd13: hdr_byte = cfg_src_ip[23:16];
                    5'd14: hdr_byte = cfg_src_ip[15:8];
                    5'd15: hdr_byte = cfg_src_ip[7:0];
                    5'd16: hdr_byte = cfg_dst_ip[31:24];
                    5'd17: hdr_byte = cfg_dst_ip[23:16];
                    5'd18: hdr_byte = cfg_dst_ip[15:8];
                    default: hdr_byte = cfg_dst_ip[7:0];
                endcase
            end else if (o < 16'd42) begin
                case (o[3:0] - 4'd2)
                    4'd0: hdr_byte = cfg_src_port[15:8];
                    4'd1: hdr_byte = cfg_src_port[7:0];
                    4'd2: hdr_byte = cfg_dst_port[15:8];
                    4'd3: hdr_byte = cfg_dst_port[7:0];
                    4'd4: hdr_byte = udp_len[15:8];
                    4'd5: hdr_byte = udp_len[7:0];
                    4'd6: hdr_byte = 8'h00;
                    default: hdr_byte = 8'h00;
                endcase
            end else if (o < 16'd46)
                hdr_byte = cfg_spi[31 - 8*(o - 16'd42) -: 8];
            else if (o < 16'd50)
                hdr_byte = seq_r[31 - 8*(o - 16'd46) -: 8];
            else
                hdr_byte = cfg_iv[95 - 8*(o - 16'd50) -: 8];
        end
    endfunction

    reg [7:0] m_byte;
    always @* begin
        if (tx_cnt < 16'd62)
            m_byte = hdr_byte(tx_cnt);
        else if (tx_cnt < ct_end)
            m_byte = tx_blk[127:120];
        else if (tx_cnt < ct_end + 16'd2)
            m_byte = (tx_cnt == ct_end) ? 8'h00 : 8'h04;
        else
            m_byte = tag_r[127 - 8*(tx_cnt - (ct_end + 16'd2)) -: 8];
    end

    assign m_tdata = m_byte;
    assign m_tvalid = (state == ST_TX);
    assign m_tlast = (state == ST_TX) && (tx_cnt == frame_n - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            blk_acc <= 128'd0;
            fcnt <= 12'd0;
            frm_len <= 12'd0;
            pt_idx <= 8'd0;
            pt_rd_addr <= 8'd0;
            pt_req <= 1'b0;
            pt_data_v <= 1'b0;
            grant_used <= 1'b0;
            ct_idx <= 8'd0;
            tx_cnt <= 16'd0;
            tag_r <= 128'd0;
            seq_r <= 32'd0;
            ip_csum_r <= 16'd0;
            tx_blk <= 128'd0;
            tx_b <= 4'd0;
            tx_blk_v <= 1'b0;
            ct_rd_idx <= 8'd0;
            gcm_req <= 1'b0;
            gcm_start <= 1'b0;
            gcm_pt_len <= 12'd0;
            gcm_nonce <= 96'd0;
            gcm_aad <= 128'd0;
            gcm_pt_valid <= 1'b0;
            gcm_ct_ready <= 1'b0;
        end else begin
            gcm_start <= 1'b0;
            gcm_pt_valid <= 1'b0;
            gcm_ct_ready <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (s_tvalid) begin
                        fcnt <= 12'd1;
                        blk_acc <= {120'd0, s_tdata};
                        state <= ST_RX;
                    end
                end
                ST_RX: begin
                    if (s_tvalid) begin
                        if ((fcnt - 12'd1) % 12'd16 == 12'd15) begin
                            frm_buf[(fcnt - 12'd1) >> 4] <= blk_acc;
                            blk_acc <= {120'd0, s_tdata};
                        end else begin
                            blk_acc <= {blk_acc[119:0], s_tdata};
                        end
                        if (s_tlast) begin
                            if ((fcnt - 12'd1) % 12'd16 != 12'd15) begin
                                case (fcnt[3:0] + 4'd1)
                                    4'd1:  frm_buf[fcnt >> 4] <= {s_tdata, 120'd0};
                                    4'd2:  frm_buf[fcnt >> 4] <= {blk_acc[7:0], s_tdata, 112'd0};
                                    4'd3:  frm_buf[fcnt >> 4] <= {blk_acc[15:8], blk_acc[7:0], s_tdata, 104'd0};
                                    4'd4:  frm_buf[fcnt >> 4] <= {blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 96'd0};
                                    4'd5:  frm_buf[fcnt >> 4] <= {blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 88'd0};
                                    4'd6:  frm_buf[fcnt >> 4] <= {blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 80'd0};
                                    4'd7:  frm_buf[fcnt >> 4] <= {blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 72'd0};
                                    4'd8:  frm_buf[fcnt >> 4] <= {blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 64'd0};
                                    4'd9:  frm_buf[fcnt >> 4] <= {blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 56'd0};
                                    4'd10: frm_buf[fcnt >> 4] <= {blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 48'd0};
                                    4'd11: frm_buf[fcnt >> 4] <= {blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 40'd0};
                                    4'd12: frm_buf[fcnt >> 4] <= {blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 32'd0};
                                    4'd13: frm_buf[fcnt >> 4] <= {blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 24'd0};
                                    4'd14: frm_buf[fcnt >> 4] <= {blk_acc[103:96], blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 16'd0};
                                    default: frm_buf[fcnt >> 4] <= {blk_acc[111:104], blk_acc[103:96], blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 8'd0};
                                endcase
                            end
                            frm_len <= fcnt + 12'd1;
                            gcm_req <= 1'b1;
                            state <= ST_ENC;
                        end else begin
                            fcnt <= fcnt + 12'd1;
                        end
                    end
                end
                ST_ENC: begin
                    if (gcm_grant && !grant_used) begin
                        grant_used <= 1'b1;
                        gcm_req <= 1'b0;
                        gcm_start <= 1'b1;
                        gcm_pt_len <= frm_len;
                        gcm_nonce <= cfg_iv;
                        gcm_aad <= {cfg_spi, seq_in, 64'd0};
                        seq_r <= seq_in;
                        ip_csum_r <= ip_csum_c;
                        pt_idx <= 8'd0;
                        pt_req <= 1'b0;
                        pt_data_v <= 1'b0;
                        ct_idx <= 8'd0;
                    end
                    if (gcm_pt_ready && !pt_req && !pt_data_v && (pt_idx < nct[7:0])) begin
                        pt_rd_addr <= pt_idx;
                        pt_req <= 1'b1;
                    end
                    if (pt_req && !pt_data_v) begin
                        pt_data_v <= 1'b1;
                    end
                    gcm_pt_valid <= pt_data_v;
                    gcm_pt_data <= pt_rd_data;
                    if (pt_data_v && gcm_pt_ready) begin
                        pt_req <= 1'b0;
                        pt_data_v <= 1'b0;
                        pt_idx <= pt_idx + 8'd1;
                    end
                    if (gcm_ct_valid && !gcm_ct_ready) begin
                        ct_buf[ct_idx] <= gcm_ct_data;
                        ct_idx <= ct_idx + 8'd1;
                    end
                    gcm_ct_ready <= gcm_ct_valid && !gcm_ct_ready;
                    if (gcm_tag_valid) begin
                        grant_used <= 1'b0;
                        tag_r <= gcm_tag;
                        tx_cnt <= 16'd0;
                        tx_blk_v <= 1'b0;
                        ct_rd_idx <= 8'd0;
                        state <= ST_TX;
                    end
                end
                ST_TX: begin
                    if (m_tready) begin
                        if (tx_cnt >= 16'd61 && tx_cnt < ct_end) begin
                            if (!tx_blk_v) begin
                                tx_blk <= ct_rd_data;
                                tx_blk_v <= 1'b1;
                                tx_b <= 4'd0;
                                ct_rd_idx <= ct_rd_idx + 8'd1;
                            end else if (tx_cnt >= 16'd62) begin
                                if (tx_b == 4'd15) begin
                                    tx_blk <= ct_rd_data;
                                    ct_rd_idx <= ct_rd_idx + 8'd1;
                                    tx_b <= 4'd0;
                                end else begin
                                    tx_blk <= {tx_blk[119:0], 8'd0};
                                    tx_b <= tx_b + 4'd1;
                                end
                            end
                        end
                        if (tx_cnt == frame_n - 16'd1) begin
                            state <= ST_IDLE;
                        end else begin
                            tx_cnt <= tx_cnt + 16'd1;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
