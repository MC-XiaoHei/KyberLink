module bridge_enc_path (
    input wire clk,
    input wire rst_n,

    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,

    input  wire [255:0] key,
    input  wire         key_load,
    input  wire [ 31:0] cfg_spi,
    input  wire [ 95:0] cfg_iv,
    input  wire [ 31:0] cfg_src_ip,
    input  wire [ 31:0] cfg_dst_ip,
    input  wire [ 15:0] cfg_src_port,
    input  wire [ 15:0] cfg_dst_port,
    input  wire [ 47:0] cfg_src_mac,
    input  wire [ 47:0] cfg_dst_mac,
    input  wire [ 31:0] seq_in,
    output wire [ 31:0] seq_out,
    output reg          seq_vld,

    output reg          gcm_start,
    input  wire         gcm_grant,
    output reg          gcm_req,
    output reg  [ 11:0] gcm_pt_len,
    output reg  [ 95:0] gcm_nonce,
    output reg  [127:0] gcm_aad,
    output wire         gcm_pt_valid,
    input  wire         gcm_pt_ready,
    output wire [127:0] gcm_pt_data,
    input  wire         gcm_ct_valid,
    output reg          gcm_ct_ready,
    input  wire [127:0] gcm_ct_data,
    input  wire         gcm_tag_valid,
    input  wire [127:0] gcm_tag,
    input  wire         gcm_busy,
    input  wire         gcm_done,

    output wire [7:0] m_tdata,
    output wire       m_tvalid,
    output wire       m_tlast,
    input  wire       m_tready,

    output reg  err_oversize
);

  localparam RX_IDLE = 1'b0;
  localparam RX_RUN  = 1'b1;
  localparam ES_IDLE = 2'd0;
  localparam ES_ENC  = 2'd1;
  localparam ES_LOAD = 2'd2;
  localparam TS_IDLE = 2'd0;
  localparam TS_TX   = 2'd1;

  reg             rx_state;
  reg     [  1:0] es;
  reg     [  1:0] ts;
  reg             grant_used;


  reg     [  1:0] rx_slot;
  reg     [  1:0] enc_slot;
  reg     [  1:0] tx_slot;
  reg     [  1:0] tx_rd_slot;
  reg     [  3:0] enc_pend;
  reg     [  3:0] ct_avail;
  reg     [  3:0] tx_busy;
  reg             frm_wr_pend;
  reg     [127:0] blk_acc;
  reg     [  3:0] blk_cnt;
  reg     [  8:0] frm_waddr;
  reg     [ 11:0] fcnt;
  reg     [  8:0] frm_wr_addr;
  reg     [127:0] frm_wr_data;
  reg     [ 11:0] frm_len_p                                                          [0:3];
  reg     [ 31:0] seq_p                                                              [0:3];
  reg     [ 15:0] total_len_p                                                        [0:3];
  reg     [ 15:0] udp_len_p                                                          [0:3];
  reg     [ 11:0] tx_len_p                                                           [0:3];
  reg     [ 31:0] tx_seq_p                                                           [0:3];
  reg     [ 15:0] tx_total_p                                                         [0:3];
  reg     [ 15:0] tx_udp_p                                                           [0:3];
  reg     [127:0] tx_tag_p                                                           [0:3];
  reg     [ 15:0] tx_csum_p                                                          [0:3];
  reg     [ 11:0] frm_len_e;
  reg     [ 11:0] pt_len_e_r;
  reg     [  3:0] pad_n_e_r;
  reg     [  7:0] pt_idx;

  reg     [127:0] pt_rd_data;
  integer         blk_b;
  reg     [ 11:0] blk_n;
  reg             pt_req;
  reg             pt_rd_done;
  reg             pt_data_v;
  reg     [  7:0] ct_idx;
  reg     [ 15:0] tx_cnt;
  reg     [127:0] tag_r;
  reg     [ 31:0] seq_r;
  reg     [ 15:0] ip_csum_r;
  reg     [ 15:0] total_len_q;
  reg     [ 15:0] udp_len_q;
  reg     [127:0] tx_blk;
  reg     [  3:0] tx_b;
  reg             tx_rd_pend;
  reg     [  8:0] rd_addr_q;
  reg     [  7:0] ct_rd_idx;
  reg     [ 15:0] frame_n_q;
  reg     [ 15:0] ct_end_q;
  reg     [  8:0] nct_q;
  reg     [  8:0] enc_nct;

  wire    [ 11:0] frm_len_now = fcnt + 12'd1;
  wire    [  3:0] pad_now = (16 - ((frm_len_now[3:0] + 4'd2) & 4'hF)) & 4'hF;
  wire    [ 11:0] pt_len_now = frm_len_now + 12'd2 + {8'd0, pad_now};
  wire    [  3:0] pad_n_e = (16 - ((frm_len_p[enc_slot][3:0] + 4'd2) & 4'hF)) & 4'hF;
  wire    [ 11:0] pt_len_e = frm_len_p[enc_slot] + 12'd2 + {8'd0, pad_n_e};
  wire    [  8:0] nct_e = {1'b0, pt_len_e[11:4]} + {8'd0, |pt_len_e[3:0]};

  function [15:0] fold16(input [31:0] s);
    begin
      fold16 = s[15:0] + s[31:16];
    end
  endfunction

  wire [15:0] ip_sum_e = 16'h4500 + total_len_p[enc_slot] + 16'h4000 + 16'h4011
                         + cfg_src_ip[31:16] + cfg_src_ip[15:0]
                         + cfg_dst_ip[31:16] + cfg_dst_ip[15:0];
  (* syn_ramstyle = "block_ram" *) reg [127:0] mem[0:511];
  wire [15:0] ip_csum_e = ~fold16({16'd0, ip_sum_e});
  assign gcm_pt_valid = pt_data_v;
  assign gcm_pt_data = pt_rd_data;
  assign s_tready = (rx_state == RX_RUN) || ((rx_state == RX_IDLE)
                     && !enc_pend[rx_slot] && !ct_avail[rx_slot] && !tx_busy[rx_slot]);
  assign seq_out = seq_r;

  always @(posedge clk) begin
    for (blk_b = 0; blk_b < 16; blk_b = blk_b + 1) begin
      blk_n = {pt_idx, 4'd0} + blk_b[11:0];
      if (blk_n < frm_len_e) pt_rd_data[127-8*blk_b-:8] <= mem_rdata[127-8*blk_b-:8];
      else if (blk_n < pt_len_e_r) begin
        if (blk_n - frm_len_e == pad_n_e_r) pt_rd_data[127-8*blk_b-:8] <= {4'd0, pad_n_e_r};
        else if (blk_n - frm_len_e == pad_n_e_r + 12'd1) pt_rd_data[127-8*blk_b-:8] <= 8'h04;
        else pt_rd_data[127-8*blk_b-:8] <= 8'h00;
      end else pt_rd_data[127-8*blk_b-:8] <= 8'h00;
    end
  end


  function [7:0] hdr_byte(input [15:0] o);
    reg [15:0] ipd;
    begin
      case (1'b1)
        o < 16'd6: hdr_byte = cfg_dst_mac[47-8*o[2:0]-:8];
        o < 16'd12: hdr_byte = cfg_src_mac[47-8*(o-16'd6)-:8];
        o < 16'd14: hdr_byte = (o == 16'd12) ? 8'h08 : 8'h00;
        o < 16'd34: begin
          ipd = o - 16'd14;
          case (ipd[4:0])
            5'd0: hdr_byte = 8'h45;
            5'd1: hdr_byte = 8'h00;
            5'd2: hdr_byte = tx_total_p[tx_rd_slot][15:8];
            5'd3: hdr_byte = tx_total_p[tx_rd_slot][7:0];
            5'd4: hdr_byte = 8'h00;
            5'd5: hdr_byte = 8'h00;
            5'd6: hdr_byte = 8'h40;
            5'd7: hdr_byte = 8'h00;
            5'd8: hdr_byte = 8'h40;
            5'd9: hdr_byte = 8'h11;
            5'd10: hdr_byte = tx_csum_p[tx_rd_slot][15:8];
            5'd11: hdr_byte = tx_csum_p[tx_rd_slot][7:0];
            5'd12: hdr_byte = cfg_src_ip[31:24];
            5'd13: hdr_byte = cfg_src_ip[23:16];
            5'd14: hdr_byte = cfg_src_ip[15:8];
            5'd15: hdr_byte = cfg_src_ip[7:0];
            5'd16: hdr_byte = cfg_dst_ip[31:24];
            5'd17: hdr_byte = cfg_dst_ip[23:16];
            5'd18: hdr_byte = cfg_dst_ip[15:8];
            default: hdr_byte = cfg_dst_ip[7:0];
          endcase
        end
        o < 16'd42: begin
          case (o[3:0] - 4'd2)
            4'd0: hdr_byte = cfg_src_port[15:8];
            4'd1: hdr_byte = cfg_src_port[7:0];
            4'd2: hdr_byte = cfg_dst_port[15:8];
            4'd3: hdr_byte = cfg_dst_port[7:0];
            4'd4: hdr_byte = tx_udp_p[tx_rd_slot][15:8];
            4'd5: hdr_byte = tx_udp_p[tx_rd_slot][7:0];
            4'd6: hdr_byte = 8'h00;
            default: hdr_byte = 8'h00;
          endcase
        end
        o < 16'd46: hdr_byte = cfg_spi[31-8*(o-16'd42)-:8];
        o < 16'd50: hdr_byte = tx_seq_p[tx_rd_slot][31-8*(o-16'd46)-:8];
        o < 16'd54: hdr_byte = tx_seq_p[tx_rd_slot][31-8*(o-16'd50)-:8];
        default: hdr_byte = cfg_iv[95-8*(o-16'd54)-:8];
      endcase
    end
  endfunction

  reg [7:0] m_byte;
  always @* begin
    if (tx_cnt < 16'd62) m_byte = hdr_byte(tx_cnt);
    else if (tx_cnt < ct_end_q) m_byte = tx_blk[127:120];
    else m_byte = tag_r[127-8*(tx_cnt-ct_end_q)-:8];
  end

  wire        tx_read_fire = (ts == TS_TX) && (!m_tvalid_q || m_tready) && (tx_cnt >= 16'd60) && (tx_cnt[3:0] == 4'd12) && (tx_cnt < ct_end_q);
  wire ct_write = (es == ES_ENC) && gcm_ct_valid && gcm_ct_ready;
  wire pt_read_fire = pt_req && !pt_data_v && !tx_read_fire;
  wire [8:0] mem_waddr = ct_write ? {enc_slot, ct_idx[6:0]} : frm_wr_addr;
  wire [127:0] mem_wdata = ct_write ? gcm_ct_data : frm_wr_data;
  wire mem_we = ct_write | frm_wr_pend;
  wire [8:0] mem_raddr = pt_read_fire ? {enc_slot, pt_idx[6:0]} : {tx_rd_slot, ct_rd_idx[6:0]};
  reg [127:0] mem_rdata;
  always @(posedge clk) begin
    if (mem_we) mem[mem_waddr] <= mem_wdata;
    mem_rdata <= mem[mem_raddr];
  end
  reg [7:0] m_byte_q;
  reg       m_tvalid_q;
  reg       m_tlast_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_byte_q   <= 8'd0;
      m_tvalid_q <= 1'b0;
      m_tlast_q  <= 1'b0;
    end else if (m_tvalid_q && !m_tready) begin
      m_byte_q   <= m_byte_q;
      m_tvalid_q <= 1'b1;
      m_tlast_q  <= m_tlast_q;
    end else begin
      m_byte_q   <= m_byte;
      m_tvalid_q <= (ts == TS_TX);
      m_tlast_q  <= (ts == TS_TX) && (tx_cnt >= frame_n_q - 16'd1);
    end
  end
  assign m_tdata  = m_byte_q;
  assign m_tvalid = m_tvalid_q;
  assign m_tlast  = m_tlast_q;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_state <= RX_IDLE;
      es <= ES_IDLE;
      ts <= TS_IDLE;
      rx_slot <= 2'd0;
      enc_slot <= 2'd0;
      tx_slot <= 2'd0;
      tx_rd_slot <= 2'd0;
      enc_pend <= 2'd0;
      ct_avail <= 4'd0;
      tx_busy <= 4'd0;
      blk_acc <= 128'd0;
      fcnt <= 12'd0;
      frm_wr_addr <= 9'd0;
      tx_rd_pend <= 1'b0;
      frm_wr_data <= 128'd0;
      frm_len_p[0] <= 12'd0;
      frm_len_p[1] <= 12'd0;
      frm_len_p[2] <= 12'd0;
      frm_len_p[3] <= 12'd0;
      seq_p[0] <= 32'd0;
      seq_p[1] <= 32'd0;
      seq_p[2] <= 32'd0;
      seq_p[3] <= 32'd0;
      total_len_p[0] <= 16'd0;
      total_len_p[1] <= 16'd0;
      total_len_p[2] <= 16'd0;
      total_len_p[3] <= 16'd0;
      udp_len_p[0] <= 16'd0;
      udp_len_p[1] <= 16'd0;
      udp_len_p[2] <= 16'd0;
      udp_len_p[3] <= 16'd0;
      tx_len_p[0] <= 12'd0;
      tx_len_p[1] <= 12'd0;
      tx_len_p[2] <= 12'd0;
      tx_len_p[3] <= 12'd0;
      tx_seq_p[0] <= 32'd0;
      tx_seq_p[1] <= 32'd0;
      tx_seq_p[2] <= 32'd0;
      tx_seq_p[3] <= 32'd0;
      tx_total_p[0] <= 16'd0;
      tx_total_p[1] <= 16'd0;
      tx_total_p[2] <= 16'd0;
      tx_total_p[3] <= 16'd0;
      tx_udp_p[0] <= 16'd0;
      tx_udp_p[1] <= 16'd0;
      tx_udp_p[2] <= 16'd0;
      tx_udp_p[3] <= 16'd0;
      tx_csum_p[0] <= 16'd0;
      tx_csum_p[1] <= 16'd0;
      tx_csum_p[2] <= 16'd0;
      tx_csum_p[3] <= 16'd0;
      tx_tag_p[0] <= 128'd0;
      tx_tag_p[1] <= 128'd0;
      tx_tag_p[2] <= 128'd0;
      tx_tag_p[3] <= 128'd0;
      frm_len_e <= 12'd0;
      pt_len_e_r <= 12'd0;
      pad_n_e_r <= 4'd0;
      pt_idx <= 8'd0;
      pt_req <= 1'b0;
      pt_rd_done <= 1'b0;
      pt_data_v <= 1'b0;
      ct_idx <= 8'd0;
      tx_cnt <= 16'd0;
      tag_r <= 128'd0;
      seq_r <= 32'd0;
      ip_csum_r <= 16'd0;
      total_len_q <= 16'd0;
      udp_len_q <= 16'd0;
      tx_blk <= 128'd0;
      tx_b <= 4'd0;
      tx_rd_pend <= 1'b0;
      rd_addr_q <= 9'd0;
      ct_rd_idx <= 8'd0;
      frame_n_q <= 16'd0;
      ct_end_q <= 16'd0;
      nct_q <= 9'd0;
      enc_nct <= 8'd0;
      gcm_start <= 1'b0;
      gcm_req <= 1'b0;
      grant_used <= 1'b0;
      gcm_pt_len <= 12'd0;
      gcm_nonce <= 96'd0;
      gcm_aad <= 128'd0;
      gcm_ct_ready <= 1'b0;
      seq_vld <= 1'b0;
      err_oversize <= 1'b0;
    end else begin
      gcm_start <= 1'b0;
      gcm_ct_ready <= 1'b0;
      seq_vld <= 1'b0;
      err_oversize <= 1'b0;
      if (es == ES_ENC) begin
        if (gcm_ct_valid && gcm_ct_ready) begin
          ct_idx <= ct_idx + 8'd1;
        end
        gcm_ct_ready <= 1'b1;
        if (gcm_pt_ready && !pt_req && !pt_data_v && (pt_idx < enc_nct)) begin
          pt_req <= 1'b1;
        end
        if (pt_read_fire) begin
          pt_rd_done <= 1'b1;
        end
        if (pt_rd_done) begin
          pt_rd_done <= 1'b0;
          pt_data_v  <= 1'b1;
        end
        if (pt_data_v && gcm_pt_ready) begin
          pt_req <= 1'b0;
          pt_data_v <= 1'b0;
          pt_idx <= pt_idx + 8'd1;
        end
        if (gcm_tag_valid) begin
          grant_used <= 1'b0;
          tx_len_p[enc_slot] <= gcm_pt_len;
          tx_seq_p[enc_slot] <= seq_p[enc_slot];
          tx_total_p[enc_slot] <= total_len_p[enc_slot];
          tx_udp_p[enc_slot] <= udp_len_p[enc_slot];
          tx_csum_p[enc_slot] <= ip_csum_r;
          tx_tag_p[enc_slot] <= gcm_tag;
          ct_avail[enc_slot] <= 1'b1;
          enc_pend[enc_slot] <= 1'b0;
          enc_slot <= enc_slot + 2'd1;
          es <= ES_IDLE;
        end
      end
      if (ts == TS_TX) begin
        if (!m_tvalid_q || m_tready) begin
          if (tx_read_fire) begin
            ct_rd_idx  <= ct_rd_idx + 8'd1;
            tx_rd_pend <= 1'b1;
            rd_addr_q  <= {tx_rd_slot, ct_rd_idx[6:0]};
          end
          if ((tx_cnt >= 16'd62) && (tx_cnt < ct_end_q)) begin
            if (tx_b == 4'd15) begin
              tx_b <= 4'd0;
            end else begin
              tx_blk <= {tx_blk[119:0], 8'd0};
              tx_b   <= tx_b + 4'd1;
            end
          end
          if (tx_rd_pend) begin
            tx_blk <= mem[rd_addr_q];
            tx_rd_pend <= 1'b0;
          end
          if (m_tvalid_q && m_tready && (tx_cnt == frame_n_q - 16'd1)) begin
            if (ct_avail[tx_slot]) begin
              ct_avail[tx_slot] <= 1'b0;
              tx_busy[tx_rd_slot] <= 1'b0;
              tx_busy[tx_slot] <= 1'b1;
              tx_rd_slot <= tx_slot;
              tx_slot <= tx_slot + 2'd1;
              frame_n_q <= 16'd78 + {4'd0, tx_len_p[tx_slot]};
              ct_end_q <= 16'd62 + {4'd0, tx_len_p[tx_slot]};
              tag_r <= tx_tag_p[tx_slot];
              tx_cnt <= 16'd0;
              tx_rd_pend <= 1'b0;
              ct_rd_idx <= 8'd0;
            end else begin
              ts <= TS_IDLE;
              tx_busy[tx_rd_slot] <= 1'b0;
            end
          end else begin
            tx_cnt <= tx_cnt + 16'd1;
          end
        end
      end

      case (rx_state)
        RX_IDLE: begin
          if (s_tvalid && s_tready) begin
            fcnt <= 12'd1;
            blk_cnt <= 4'd1;
            blk_acc <= {120'd0, s_tdata};
            frm_waddr <= {rx_slot, 7'd0};
            rx_state <= RX_RUN;
          end
        end
        RX_RUN: begin
          if (s_tvalid && s_tready) begin
            if (blk_cnt == 4'd15) begin
              frm_waddr <= {rx_slot, frm_waddr[6:0] + 7'd1};
              blk_acc   <= 128'd0;
              blk_cnt   <= 4'd0;
            end else begin
              blk_acc <= {blk_acc[119:0], s_tdata};
              blk_cnt <= blk_cnt + 4'd1;
            end
            if (s_tlast) begin
              case (blk_cnt)
                4'd1: frm_wr_data <= {blk_acc[7:0], s_tdata, 112'd0};
                4'd2: frm_wr_data <= {blk_acc[15:8], blk_acc[7:0], s_tdata, 104'd0};
                4'd3: frm_wr_data <= {blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 96'd0};
                4'd4:
                frm_wr_data <= {
                  blk_acc[31:24], blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 88'd0
                };
                4'd5:
                frm_wr_data <= {
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  80'd0
                };
                4'd6:
                frm_wr_data <= {
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  72'd0
                };
                4'd7:
                frm_wr_data <= {
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  64'd0
                };
                4'd8:
                frm_wr_data <= {
                  blk_acc[63:56],
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  56'd0
                };
                4'd9:
                frm_wr_data <= {
                  blk_acc[71:64],
                  blk_acc[63:56],
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  48'd0
                };
                4'd10:
                frm_wr_data <= {
                  blk_acc[79:72],
                  blk_acc[71:64],
                  blk_acc[63:56],
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  40'd0
                };
                4'd11:
                frm_wr_data <= {
                  blk_acc[87:80],
                  blk_acc[79:72],
                  blk_acc[71:64],
                  blk_acc[63:56],
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  32'd0
                };
                4'd12:
                frm_wr_data <= {
                  blk_acc[95:88],
                  blk_acc[87:80],
                  blk_acc[79:72],
                  blk_acc[71:64],
                  blk_acc[63:56],
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  24'd0
                };
                4'd13:
                frm_wr_data <= {
                  blk_acc[103:96],
                  blk_acc[95:88],
                  blk_acc[87:80],
                  blk_acc[79:72],
                  blk_acc[71:64],
                  blk_acc[63:56],
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  16'd0
                };
                4'd14:
                frm_wr_data <= {
                  blk_acc[111:104],
                  blk_acc[103:96],
                  blk_acc[95:88],
                  blk_acc[87:80],
                  blk_acc[79:72],
                  blk_acc[71:64],
                  blk_acc[63:56],
                  blk_acc[55:48],
                  blk_acc[47:40],
                  blk_acc[39:32],
                  blk_acc[31:24],
                  blk_acc[23:16],
                  blk_acc[15:8],
                  blk_acc[7:0],
                  s_tdata,
                  8'd0
                };
                4'd0:
                frm_wr_data <= {s_tdata, 120'd0};
                default: frm_wr_data <= {blk_acc[119:0], s_tdata};
              endcase
              if (blk_cnt != 4'd15) begin
                frm_wr_pend <= 1'b1;
                frm_wr_addr <= frm_waddr;
              end
              if (pt_len_now <= 12'd1432) begin
                frm_len_p[rx_slot] <= fcnt + 12'd1;
                seq_p[rx_slot] <= seq_r;
                seq_r <= seq_r + 32'd1;
                total_len_p[rx_slot] <= 16'd64 + {4'd0, pt_len_now};
                udp_len_p[rx_slot] <= 16'd44 + {4'd0, pt_len_now};
                enc_pend[rx_slot] <= 1'b1;
              end else begin
                err_oversize <= 1'b1;
              end
              rx_slot  <= rx_slot + 2'd1;
              rx_state <= RX_IDLE;
            end else begin
              fcnt <= fcnt + 12'd1;
            end
          end
        end
        default: rx_state <= RX_IDLE;
      endcase
      if (frm_wr_pend && !ct_write &&
          !(s_tvalid && s_tready && s_tlast && (blk_cnt != 4'd15))) begin
        frm_wr_pend <= 1'b0;
      end
      if (rx_state == RX_RUN && s_tvalid && s_tready && (blk_cnt == 4'd15)) begin
        frm_wr_addr <= frm_waddr;
        frm_wr_data <= {blk_acc[119:0], s_tdata};
        frm_wr_pend <= 1'b1;
      end
      if (es == ES_IDLE) begin
        if (enc_pend[enc_slot]) begin
          gcm_req <= 1'b1;
          es <= ES_LOAD;
        end else if (enc_pend != 4'd0) begin
          enc_slot <= enc_slot + 2'd1;
        end
      end
      if (es == ES_LOAD) begin
        if (gcm_grant && !grant_used) begin
          grant_used <= 1'b1;
          gcm_req <= 1'b0;
          frm_len_e <= frm_len_p[enc_slot];
          pt_len_e_r <= pt_len_e;
          pad_n_e_r <= pad_n_e;
          ct_idx <= 8'd0;
          pt_idx <= 8'd0;
          pt_req <= 1'b0;
          pt_rd_done <= 1'b0;
          pt_data_v <= 1'b0;
          gcm_start <= 1'b1;
          gcm_pt_len <= pt_len_e;
          gcm_nonce <= {seq_p[enc_slot], cfg_iv[95:32]};
          gcm_aad <= {cfg_spi, seq_p[enc_slot], 64'd0};
          total_len_q <= total_len_p[enc_slot];
          udp_len_q <= udp_len_p[enc_slot];
          ip_csum_r <= ip_csum_e;
          enc_nct <= nct_e[7:0];
          nct_q <= nct_e;
          seq_vld <= 1'b1;
          es <= ES_ENC;
        end
      end
      if ((ts == TS_IDLE) && !ct_avail[tx_slot] && (ct_avail != 4'd0)) begin
        tx_slot <= tx_slot + 2'd1;
      end
      if (ct_avail[tx_slot] && (ts == TS_IDLE)) begin
        ct_avail[tx_slot] <= 1'b0;
        tx_busy[tx_slot] <= 1'b1;
        tx_rd_slot <= tx_slot;
        tx_slot <= tx_slot + 2'd1;
        frame_n_q <= 16'd78 + {4'd0, tx_len_p[tx_slot]};
        ct_end_q <= 16'd62 + {4'd0, tx_len_p[tx_slot]};
        tag_r <= tx_tag_p[tx_slot];
        tx_cnt <= 16'd0;
        tx_rd_pend <= 1'b0;
        ct_rd_idx <= 8'd0;
        ts <= TS_TX;
      end
      if (key_load) begin
        seq_r <= seq_in;
      end
    end
  end

endmodule
