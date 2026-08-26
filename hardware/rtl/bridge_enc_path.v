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
    output wire [31:0]   seq_out,
    output wire          gcm_active,

    input  wire          gcm_grant,
    output reg           gcm_req,
    output reg           gcm_start,
    output reg  [11:0]   gcm_pt_len,
    output reg  [95:0]   gcm_nonce,
    output reg  [127:0]  gcm_aad,
    output wire          gcm_pt_valid,
    input  wire          gcm_pt_ready,
    output wire [127:0]  gcm_pt_data,
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

    (* syn_ramstyle = "block" *) reg [63:0] frm_lo [0:127];
    (* syn_ramstyle = "block" *) reg [63:0] frm_hi [0:127];
    (* syn_ramstyle = "block" *) reg [63:0] ct_lo [0:127];
    (* syn_ramstyle = "block" *) reg [63:0] ct_hi [0:127];
    reg         frm_wr_pend;
    reg [6:0]   frm_wr_addr;
    reg [127:0] frm_wr_data;
    reg [127:0] blk_acc;
    reg [11:0]  fcnt;
    reg [11:0]  frm_len;
    reg [7:0]   pt_idx;
    reg [7:0]   pt_rd_addr;
    reg [127:0] pt_rd_data;
    integer     blk_b;
    reg [11:0]  blk_n;
    reg         pt_req;
    reg         pt_data_v;
    reg         grant_used;
    reg [7:0]   ct_idx;
    reg [15:0]  tx_cnt;
    reg [127:0] tag_r;
    reg [31:0]  seq_r;
    reg         first_pkt;
    reg [15:0]  ip_csum_r;
    reg [15:0]  total_len_q;
    reg [15:0]  udp_len_q;
    reg [127:0] tx_blk;
    reg [3:0]   tx_b;
    reg         tx_blk_v;
    reg [7:0]   ct_rd_idx;
    reg [127:0] ct_rd_data;

    wire [3:0]  pad_n = (16 - ((frm_len[3:0] + 4'd2) & 4'hF)) & 4'hF;
    wire [11:0] pt_len_w = frm_len + 12'd2 + {8'd0, pad_n};
    wire [15:0] udp_len = 16'd44 + {4'd0, pt_len_w};
    wire [15:0] total_len = 16'd64 + {4'd0, pt_len_w};
    wire [15:0] frame_n = 16'd78 + {4'd0, pt_len_w};
    wire [15:0] ct_end = 16'd62 + {4'd0, pt_len_w};
    wire [8:0]  nct = {1'b0, pt_len_w[11:4]} + {8'd0, |pt_len_w[3:0]};
    reg [8:0] nct_q;
    always @(posedge clk) nct_q <= nct;
    reg [11:0] pt_len_w_q;
    always @(posedge clk) pt_len_w_q <= pt_len_w;

    function [15:0] fold16(input [31:0] s);
        begin
            fold16 = s[15:0] + s[31:16];
        end
    endfunction

    wire [15:0] ip_sum = 16'h4500 + total_len_q + 16'h4000 + 16'h4011
                       + cfg_src_ip[31:16] + cfg_src_ip[15:0]
                       + cfg_dst_ip[31:16] + cfg_dst_ip[15:0];
    reg [15:0] ip_sum_q;
    always @(posedge clk) ip_sum_q <= ip_sum;
    wire [15:0] ip_csum_c = ~fold16({16'd0, ip_sum_q});
    reg gcm_start_q1;
    always @(posedge clk) begin
        gcm_start_q1 <= gcm_start;
        if (gcm_start_q1) ip_csum_r <= ip_csum_c;
    end
    assign gcm_pt_valid = pt_data_v;
    assign gcm_pt_data  = pt_rd_data;
    assign seq_out  = seq_r;
    assign gcm_active = grant_used;
    assign s_tready = (state == ST_IDLE) || (state == ST_RX);

    always @(posedge clk) begin
        for (blk_b = 0; blk_b < 16; blk_b = blk_b + 1) begin
            blk_n = {pt_rd_addr, 4'd0} + blk_b[11:0];
            if (blk_n < frm_len)
                pt_rd_data[127 - 8*blk_b -: 8] <= (blk_b < 8) ?
                    frm_hi[pt_rd_addr][63 - 8*blk_b -: 8] :
                    frm_lo[pt_rd_addr][127 - 8*blk_b -: 8];
            else if (blk_n < pt_len_w_q) begin
                if (blk_n - frm_len == pad_n)
                    pt_rd_data[127 - 8*blk_b -: 8] <= {4'd0, pad_n};
                else if (blk_n - frm_len == pad_n + 12'd1)
                    pt_rd_data[127 - 8*blk_b -: 8] <= 8'h04;
                else
                    pt_rd_data[127 - 8*blk_b -: 8] <= 8'h00;
            end else
                pt_rd_data[127 - 8*blk_b -: 8] <= 8'h00;
        end
    end
    always @(posedge clk) begin
        ct_rd_data <= {ct_hi[ct_rd_idx], ct_lo[ct_rd_idx]};
    end

    function [7:0] hdr_byte(input [15:0] o);
        reg [15:0] ipd;
        begin
            case (1'b1)
                o < 16'd6: hdr_byte = cfg_dst_mac_q[47 - 8*o[2:0] -: 8];
                o < 16'd12: hdr_byte = cfg_src_mac_q[47 - 8*(o - 16'd6) -: 8];
                o < 16'd14: hdr_byte = (o == 16'd12) ? 8'h08 : 8'h00;
                o < 16'd34: begin
                ipd = o - 16'd14;
                case (ipd[4:0])
                    5'd0: hdr_byte = 8'h45;
                    5'd1: hdr_byte = 8'h00;
                    5'd2: hdr_byte = total_len_q[15:8];
                    5'd3: hdr_byte = total_len_q[7:0];
                    5'd4: hdr_byte = 8'h00;
                    5'd5: hdr_byte = 8'h00;
                    5'd6: hdr_byte = 8'h40;
                    5'd7: hdr_byte = 8'h00;
                    5'd8: hdr_byte = 8'h40;
                    5'd9: hdr_byte = 8'h11;
                    5'd10: hdr_byte = ip_csum_r[15:8];
                    5'd11: hdr_byte = ip_csum_r[7:0];
                    5'd12: hdr_byte = cfg_src_ip_q[31:24];
                    5'd13: hdr_byte = cfg_src_ip_q[23:16];
                    5'd14: hdr_byte = cfg_src_ip_q[15:8];
                    5'd15: hdr_byte = cfg_src_ip_q[7:0];
                    5'd16: hdr_byte = cfg_dst_ip_q[31:24];
                    5'd17: hdr_byte = cfg_dst_ip_q[23:16];
                    5'd18: hdr_byte = cfg_dst_ip_q[15:8];
                    default: hdr_byte = cfg_dst_ip_q[7:0];
                endcase
                end
                o < 16'd42: begin
                case (o[3:0] - 4'd2)
                    4'd0: hdr_byte = cfg_src_port_q[15:8];
                    4'd1: hdr_byte = cfg_src_port_q[7:0];
                    4'd2: hdr_byte = cfg_dst_port_q[15:8];
                    4'd3: hdr_byte = cfg_dst_port_q[7:0];
                    4'd4: hdr_byte = udp_len_q[15:8];
                    4'd5: hdr_byte = udp_len_q[7:0];
                    4'd6: hdr_byte = 8'h00;
                    default: hdr_byte = 8'h00;
                endcase
                end
                o < 16'd46: hdr_byte = cfg_spi_q[31 - 8*(o - 16'd42) -: 8];
                o < 16'd50: hdr_byte = seq_r[31 - 8*(o - 16'd46) -: 8];
                o < 16'd54: hdr_byte = seq_r[31 - 8*(o - 16'd50) -: 8];
                default: hdr_byte = cfg_iv_q[95 - 8*(o - 16'd54) -: 8];
            endcase
        end
    endfunction

    reg [31:0] cfg_src_ip_q;
    reg [31:0] cfg_dst_ip_q;
    reg [15:0] cfg_src_port_q;
    reg [15:0] cfg_dst_port_q;
    reg [47:0] cfg_src_mac_q;
    reg [47:0] cfg_dst_mac_q;
    reg [31:0] cfg_spi_q;
    reg [95:0] cfg_iv_q;
    always @(posedge clk) begin
        cfg_src_ip_q <= cfg_src_ip;
        cfg_dst_ip_q <= cfg_dst_ip;
        cfg_src_port_q <= cfg_src_port;
        cfg_dst_port_q <= cfg_dst_port;
        cfg_src_mac_q <= cfg_src_mac;
        cfg_dst_mac_q <= cfg_dst_mac;
        cfg_spi_q <= cfg_spi;
        cfg_iv_q <= cfg_iv;
    end
    reg [7:0] m_byte;
    reg [15:0] frame_n_q;
    reg [15:0] ct_end_q;
    always @* begin
        if (tx_cnt < 16'd62)
            m_byte = hdr_byte(tx_cnt);
        else if (tx_cnt < ct_end_q)
            m_byte = tx_blk[127:120];
        else
            m_byte = tag_r[127 - 8*(tx_cnt - ct_end_q) -: 8];
    end

    reg [7:0] m_tdata_r;
    reg       m_tvalid_r;
    reg       m_tlast_r;
    assign m_tdata = m_tdata_r;
    assign m_tvalid = m_tvalid_r;
    assign m_tlast = m_tlast_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            frame_n_q <= 16'd0;
            ct_end_q <= 16'd0;
            m_tvalid_r <= 1'b0;
            blk_acc <= 128'd0;
            fcnt <= 12'd0;
            frm_wr_pend <= 1'b0;
            frm_wr_addr <= 7'd0;
            frm_wr_data <= 128'd0;
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
            first_pkt <= 1'b1;
            total_len_q <= 16'd0;
            udp_len_q <= 16'd0;
            tx_blk <= 128'd0;
            tx_b <= 4'd0;
            tx_blk_v <= 1'b0;
            ct_rd_idx <= 8'd0;
            gcm_req <= 1'b0;
            gcm_start <= 1'b0;
            gcm_pt_len <= 12'd0;
            gcm_nonce <= 96'd0;
            gcm_aad <= 128'd0;
            gcm_ct_ready <= 1'b0;
        end else begin
            gcm_start <= 1'b0;
            gcm_ct_ready <= 1'b0;
            frame_n_q <= frame_n;
            ct_end_q <= ct_end;
            case (state)
                ST_IDLE: begin
                    m_tvalid_r <= 1'b0;
                    if (s_tvalid) begin
                        fcnt <= 12'd1;
                        blk_acc <= {120'd0, s_tdata};
                        state <= ST_RX;
                    end
                end
                ST_RX: begin
                    if (s_tvalid) begin
                        if (fcnt[3:0] == 4'd0) begin
                            frm_lo[(fcnt - 12'd1) >> 4] <= blk_acc[63:0];
                            frm_hi[(fcnt - 12'd1) >> 4] <= blk_acc[127:64];
                            blk_acc <= {120'd0, s_tdata};
                        end else begin
                            blk_acc <= {blk_acc[119:0], s_tdata};
                        end
                        if (s_tlast) begin
                            if (fcnt[3:0] != 4'd0) begin
                                frm_wr_pend <= 1'b1;
                                frm_wr_addr <= fcnt >> 4;
                                case (fcnt[3:0] + 4'd1)
                                    4'd1:  frm_wr_data <= {s_tdata, 120'd0};
                                    4'd2:  frm_wr_data <= {blk_acc[7:0], s_tdata, 112'd0};
                                    4'd3:  frm_wr_data <= {blk_acc[15:8], blk_acc[7:0], s_tdata, 104'd0};
                                    4'd4:  frm_wr_data <= {blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 96'd0};
                                    4'd5:  frm_wr_data <= {blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 88'd0};
                                    4'd6:  frm_wr_data <= {blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 80'd0};
                                    4'd7:  frm_wr_data <= {blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 72'd0};
                                    4'd8:  frm_wr_data <= {blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 64'd0};
                                    4'd9:  frm_wr_data <= {blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 56'd0};
                                    4'd10: frm_wr_data <= {blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 48'd0};
                                    4'd11: frm_wr_data <= {blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 40'd0};
                                    4'd12: frm_wr_data <= {blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 32'd0};
                                    4'd13: frm_wr_data <= {blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 24'd0};
                                    4'd14: frm_wr_data <= {blk_acc[103:96], blk_acc[95:88], blk_acc[87:80], blk_acc[79:72], blk_acc[71:64], blk_acc[63:56], blk_acc[55:48], blk_acc[47:40], blk_acc[39:32], blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 16'd0};
                                    default: frm_wr_data <= {blk_acc[119:0], s_tdata};
                                endcase
                            end
                            frm_len <= fcnt + 12'd1;
                            if (first_pkt) begin
                                first_pkt <= 1'b0;
                                seq_r <= seq_in;
                            end
                            gcm_req <= 1'b1;
                            state <= ST_ENC;
                        end else begin
                            fcnt <= fcnt + 12'd1;
                        end
                    end
                end
                ST_ENC: begin
                    if (frm_wr_pend) begin
                        frm_lo[frm_wr_addr] <= frm_wr_data[63:0];
                        frm_hi[frm_wr_addr] <= frm_wr_data[127:64];
                        frm_wr_pend <= 1'b0;
                    end
                    if (gcm_grant && !grant_used) begin
                        grant_used <= 1'b1;
                        gcm_req <= 1'b0;
                        gcm_start <= 1'b1;
                        gcm_pt_len <= pt_len_w;
                        gcm_nonce <= {seq_r, cfg_iv[95:32]};
                        gcm_aad <= {cfg_spi, seq_r, 64'd0};
                        total_len_q <= total_len;
                        udp_len_q <= udp_len;
                        pt_idx <= 8'd0;
                        pt_req <= 1'b0;
                        pt_data_v <= 1'b0;
                        ct_idx <= 8'd0;
                    end
                    if (gcm_pt_ready && !pt_req && !pt_data_v && (pt_idx < nct_q[7:0])) begin
                        pt_rd_addr <= pt_idx;
                        pt_req <= 1'b1;
                    end
                    if (pt_req && !pt_data_v) begin
                        pt_data_v <= 1'b1;
                    end
                    if (pt_data_v && gcm_pt_ready) begin
                        pt_req <= 1'b0;
                        pt_data_v <= 1'b0;
                        pt_idx <= pt_idx + 8'd1;
                    end
                    if (gcm_ct_valid && gcm_ct_ready) begin
                        ct_lo[ct_idx] <= gcm_ct_data[63:0];
                        ct_hi[ct_idx] <= gcm_ct_data[127:64];
                        ct_idx <= ct_idx + 8'd1;
                    end
                    gcm_ct_ready <= 1'b1;
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
                    m_tvalid_r <= 1'b1;
                    m_tdata_r <= m_byte;
                    m_tlast_r <= (tx_cnt == frame_n_q - 16'd1);
                    if (m_tready) begin
                        if (tx_cnt >= 16'd61 && tx_cnt < ct_end_q) begin
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
                        if (tx_cnt == frame_n_q - 16'd1) begin
                            seq_r <= seq_r + 32'd1;
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
