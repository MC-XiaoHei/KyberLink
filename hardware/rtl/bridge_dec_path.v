module bridge_dec_path (
    input wire clk,
    input wire rst_n,

    input  wire [7:0] s_tdata,
    input  wire       s_tvalid,
    input  wire       s_tlast,
    output wire       s_tready,

    input wire [255:0] key,
    input wire         key_load,

    output reg          gcm_start,
    output reg  [ 11:0] gcm_pt_len,
    output reg  [ 95:0] gcm_nonce,
    output reg  [127:0] gcm_aad,
    output wire         gcm_pt_valid,
    input  wire         gcm_pt_ready,
    output wire [127:0] gcm_pt_data,
    input  wire         gcm_ct_valid,
    output wire         gcm_ct_ready,
    input  wire [127:0] gcm_ct_data,
    input  wire         gcm_tag_valid,
    input  wire [127:0] gcm_tag,
    input  wire         gcm_busy,
    input  wire         gcm_done,

    output wire [7:0] m_tdata,
    output wire       m_tvalid,
    output wire       m_tlast,
    input  wire       m_tready,
    output reg        tag_ok,

    input  wire soft_rst,
    input  wire [31:0] seq_init,
    output reg  err_badtag,
    output reg  err_badpad,
    output reg  err_replay
);

  localparam RX_IDLE = 1'b0;
  localparam RX_RUN  = 1'b1;
  localparam DS_IDLE = 2'd0;
  localparam DS_LOAD = 2'd1;
  localparam DS_RUN  = 2'd2;
  localparam DS_TAG  = 2'd3;
  localparam TS_IDLE = 2'd0;
  localparam TS_TX   = 2'd1;

  reg rx_state;
  reg [1:0] ds;
  reg tag_ok_q;
  reg [11:0] out_len_c;
  reg [1:0] ts;


  reg rx_sel;
  reg rx_r_sel;
  reg dec_sel;
  reg ct_w_sel;
  reg ct_r_sel;
  reg tx_rs;
  reg [127:0] ct_rd_data;
  reg [1:0] dec_pend;
  reg [1:0] ct_avail;
  reg [1:0] tx_busy;
  reg [143:0] tail18;
  reg [127:0] blk_acc;
  reg [3:0] frm16;
  reg [6:0] fb_idx;
  reg [11:0] fcnt;
  reg frm_wr_pend;
  reg [7:0] frm_wr_addr;
  reg [127:0] frm_wr_data;
  reg [11:0] ct_len_p[0:1];
  reg [31:0] spi_p[0:1];
  reg [31:0] seq_p[0:1];
  reg [95:0] iv_p[0:1];
  reg [127:0] tag_p[0:1];
  reg [11:0] out_len_p[0:1];
  reg [7:0] pt_idx;
  reg [7:0] pt_rd_addr;
  reg [127:0] pt_rd_data;
  reg pt_req;
  reg pt_data_v;
  reg [8:0] nct_q;
  reg [7:0] ct_idx;
  reg [7:0] ct_wr;
  reg [127:0] tail_pt;
  reg [7:0] pad_len_r;
  reg [15:0] tx_cnt;
  reg [7:0] tx_rd_idx;
  reg [127:0] tx_blk;
  reg [3:0] tx_b;
  reg tx_blk_v;
  reg [11:0] out_len_q;
  reg [31:0] last_seq_r;
  reg [63:0] win_r;
  reg [7:0] m_tdata_r;
  reg m_tvalid_r;
  reg m_tlast_r;

  reg [127:0] tag_q;
  reg tag_valid_q;
  wire [127:0] tag_w = tag_p[dec_sel];
  wire [11:0] ct_len_w = fcnt + 12'd1 - 12'd36;
  wire [8:0] nct = {1'b0, ct_len_p[dec_sel][11:4]} + {8'd0, |ct_len_p[dec_sel][3:0]};
  wire [8:0] tx_nct_w = {1'b0, out_len_q[11:4]} + {8'd0, |out_len_q[3:0]};
  wire [11:0] pad_ct_w = ct_len_p[dec_sel] - 12'd2;
  wire [3:0] pad_off_w = pad_ct_w[3:0];
  wire [7:0] pad_len_w = tail_pt[127-8*pad_off_w-:8];
  wire [11:0] out_len_w = ct_len_p[dec_sel] - 12'd2 - {8'd0, pad_len_r};
  wire pad_ok_w = (pad_len_r <= 8'd15) &&
                    (ct_len_p[dec_sel] >= (12'd2 + {8'd0, pad_len_r} + 12'd1));
  wire tag_ok_w = tag_valid_q && (tag_q[63:0] == tag_w[63:0]) && (tag_q[127:64] == tag_w[127:64]);
  (* syn_ramstyle = "block_ram" *) reg [127:0] frm[0:255];
  (* syn_ramstyle = "block_ram" *) reg [127:0] ct[0:255];
  wire [31:0] seq_fwd_w = seq_p[rx_sel] - last_seq_r;
  wire seq_new_w = (seq_fwd_w != 32'd0) && (seq_fwd_w < 32'h8000_0000);
  wire [31:0] seq_back_w = last_seq_r - seq_p[rx_sel];
  wire seq_rx_ok_c = seq_new_w ? 1'b1 : ((seq_back_w != 32'd0) && (seq_back_w < 32'd64) && !win_r[seq_p[rx_sel][5:0]]);
  reg seq_rx_ok_q;
  wire seq_rx_ok = seq_rx_ok_q;

  always @(posedge clk) begin
    pt_rd_data <= frm[{dec_sel, pt_rd_addr[6:0]}];
  end
  assign gcm_pt_valid = pt_data_v;
  assign gcm_pt_data = pt_rd_data;
  assign gcm_ct_ready = (ct_wr < 8'd96);
  assign m_tdata = m_tdata_r;
  assign m_tvalid = m_tvalid_r;
  assign s_tready = (rx_state == RX_RUN) || ((rx_state == RX_IDLE) && !dec_pend[rx_sel]);
  assign m_tlast = m_tlast_r;


  always @(posedge clk) begin
    seq_rx_ok_q <= seq_rx_ok_c;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tag_q <= 128'd0;
      tag_valid_q <= 1'b0;
    end else begin
      tag_q <= gcm_tag;
      tag_valid_q <= gcm_tag_valid;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_state <= RX_IDLE;
      ds <= DS_IDLE;
      ts <= TS_IDLE;
      rx_sel <= 1'b0;
      rx_r_sel <= 1'b0;
      dec_sel <= 1'b0;
      ct_w_sel <= 1'b0;
      ct_r_sel <= 1'b0;
      tx_rs <= 1'b0;
      dec_pend <= 2'd0;
      ct_avail <= 2'd0;
      tx_busy <= 2'd0;
      tail18 <= 144'd0;
      blk_acc <= 128'd0;
      frm16 <= 4'd0;
      fb_idx <= 7'd0;
      fcnt <= 12'd0;
      frm_wr_pend <= 1'b0;
      frm_wr_addr <= 9'd0;
      frm_wr_data <= 128'd0;
      ct_len_p[0] <= 12'd0;
      ct_len_p[1] <= 12'd0;
      spi_p[0] <= 32'd0;
      spi_p[1] <= 32'd0;
      seq_p[0] <= 32'd0;
      seq_p[1] <= 32'd0;
      iv_p[0] <= 96'd0;
      iv_p[1] <= 96'd0;
      tag_p[0] <= 128'd0;
      tag_p[1] <= 128'd0;
      out_len_p[0] <= 12'd0;
      out_len_p[1] <= 12'd0;
      pt_idx <= 8'd0;
      pt_rd_addr <= 8'd0;
      pt_req <= 1'b0;
      pt_data_v <= 1'b0;
      nct_q <= 9'd0;
      ct_idx <= 8'd0;
      ct_wr <= 8'd0;
      tail_pt <= 128'd0;
      pad_len_r <= 8'd0;
      tx_cnt <= 16'd0;
      tx_rd_idx <= 8'd0;
      tx_blk <= 128'd0;
      tx_b <= 4'd0;
      tx_blk_v <= 1'b0;
      out_len_q <= 12'd0;
      last_seq_r <= 32'hFFFF_FFFF;
      win_r <= 64'd0;
      m_tdata_r <= 8'd0;
      m_tvalid_r <= 1'b0;
      m_tlast_r <= 1'b0;
      tag_ok <= 1'b0;
      tag_ok_q <= 1'b0;
      err_badtag <= 1'b0;
      err_badpad <= 1'b0;
      err_replay <= 1'b0;
      gcm_start <= 1'b0;
      gcm_pt_len <= 12'd0;
      gcm_nonce <= 96'd0;
      gcm_aad <= 128'd0;
    end else begin
      gcm_start <= 1'b0;
      pad_len_r <= pad_len_w;
      tag_ok <= tag_ok_q;
      err_badtag <= 1'b0;
      err_badpad <= 1'b0;
      err_replay <= 1'b0;
      if (frm_wr_pend) begin
        frm[frm_wr_addr] <= frm_wr_data;
        frm_wr_pend <= 1'b0;
      end else if (rx_state == RX_RUN && s_tvalid && s_tready && (frm16 == 4'd15)) begin
        frm[{rx_sel, fb_idx}] <= {blk_acc[119:56], blk_acc[55:0], s_tdata};
      end
      case (rx_state)
        RX_IDLE: begin
          if (s_tvalid && s_tready) begin
            tail18 <= {tail18[135:0], s_tdata};
            spi_p[rx_sel][31:24] <= s_tdata;
            fcnt <= 12'd1;
            blk_acc <= {120'd0, s_tdata};
            frm16 <= 4'd0;
            fb_idx <= 7'd0;
            rx_state <= RX_RUN;
          end
        end
        RX_RUN: begin
          if (s_tvalid && s_tready) begin
            tail18 <= {tail18[135:0], s_tdata};
            if (fcnt < 12'd4) spi_p[rx_sel][31-8*fcnt[1:0]-:8] <= s_tdata;
            else if (fcnt < 12'd8) seq_p[rx_sel][31-8*(fcnt-12'd4)-:8] <= s_tdata;
            else if (fcnt < 12'd20) iv_p[rx_sel][95-8*(fcnt-12'd8)-:8] <= s_tdata;
            else begin
              if (frm16 == 4'd15) begin
                fb_idx <= fb_idx + 7'd1;
                frm16  <= 4'd0;
              end else if (frm16 == 4'd0) begin
                frm16   <= 4'd1;
                blk_acc <= {120'd0, s_tdata};
              end else begin
                frm16   <= frm16 + 4'd1;
                blk_acc <= {blk_acc[119:0], s_tdata};
              end
            end
            if (s_tlast) begin
              if (frm16 != 4'd15) begin
                frm_wr_pend <= 1'b1;
                frm_wr_addr <= {rx_sel, fb_idx};
                case (frm16)
                  4'd0: frm_wr_data <= {s_tdata, 120'd0};
                  4'd1: frm_wr_data <= {blk_acc[7:0], s_tdata, 112'd0};
                  4'd2: frm_wr_data <= {blk_acc[15:8], blk_acc[7:0], s_tdata, 104'd0};
                  4'd3:
                  frm_wr_data <= {blk_acc[23:16], blk_acc[15:8], blk_acc[7:0], s_tdata, 96'd0};
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
                  default: frm_wr_data <= {s_tdata, 120'd0};
                endcase
              end
              ct_len_p[rx_sel] <= fcnt + 12'd1 - 12'd36;
              tag_p[rx_sel] <= {tail18[119:0], s_tdata};
              if (seq_rx_ok && (fcnt < 12'd2082)) begin
                dec_pend[rx_sel] <= 1'b1;
                if (seq_new_w) last_seq_r <= seq_p[rx_sel];
                else win_r[seq_p[rx_sel][5:0]] <= 1'b1;
              end else if (!seq_rx_ok) begin
                err_replay <= 1'b1;
              end
              rx_sel   <= ~rx_sel;
              rx_state <= RX_IDLE;
            end else begin
              fcnt <= fcnt + 12'd1;
            end
          end
        end
        default: rx_state <= RX_IDLE;
      endcase
      if (ds == DS_IDLE) begin
        if (dec_pend[rx_r_sel] && !tx_busy[rx_r_sel]) begin
          dec_sel <= rx_r_sel;
          ds <= DS_LOAD;
        end else if (dec_pend[~rx_r_sel] && !tx_busy[~rx_r_sel]) begin
          dec_sel <= ~rx_r_sel;
          rx_r_sel <= ~rx_r_sel;
          ds <= DS_LOAD;
        end
      end
      if (ds == DS_LOAD) begin
        ct_idx <= 8'd0;
        ct_wr <= 8'd0;
        pt_idx <= 8'd0;
        pt_rd_addr <= 8'd0;
        pt_req <= 1'b0;
        pt_data_v <= 1'b0;
        tail_pt <= 128'd0;
        pad_len_r <= 8'd0;
        nct_q <= nct;
        gcm_start <= 1'b1;
        gcm_pt_len <= ct_len_p[dec_sel];
        gcm_nonce <= iv_p[dec_sel];
        gcm_aad <= {spi_p[dec_sel], seq_p[dec_sel], 64'd0};
        ds <= DS_RUN;
      end
      if (ds == DS_RUN) begin
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
          ct[{ct_w_sel, ct_idx[6:0]}] <= gcm_ct_data;
          ct_idx <= ct_idx + 8'd1;
          ct_wr <= ct_wr + 8'd1;
          tail_pt <= gcm_ct_data;
        end
        if (tag_valid_q) begin
          tag_ok_q <= tag_ok_w && pad_ok_w;
          out_len_c <= out_len_w;
          ds <= DS_TAG;
        end
      end
      if (ds == DS_TAG) begin
        if (!tag_ok_q) begin
          if (tag_q[63:0] != tag_w[63:0] || tag_q[127:64] != tag_w[127:64])
            err_badtag <= 1'b1;
          else
            err_badpad <= 1'b1;
        end
        if (tag_ok_q) begin
          out_len_p[ct_w_sel] <= out_len_c;
          ct_avail[ct_w_sel] <= 1'b1;
          ct_w_sel <= ct_w_sel + 1'd1;
        end
        dec_pend[dec_sel] <= 1'b0;
        ds <= DS_IDLE;
      end
      if (ts == TS_TX) begin
        if (m_tvalid_r && !m_tready) begin
          m_tdata_r  <= m_tdata_r;
          m_tvalid_r <= 1'b1;
          m_tlast_r  <= m_tlast_r;
        end else begin
          m_tdata_r  <= tx_blk[127:120];
          m_tvalid_r <= tx_blk_v;
          m_tlast_r  <= tx_blk_v && (tx_cnt == out_len_q - 16'd1);
        end
        if (m_tready && tx_blk_v) begin
          if (tx_cnt == out_len_q - 16'd1) begin
            if (ct_avail[ct_r_sel]) begin
              ct_avail[ct_r_sel] <= 1'b0;
              tx_busy[tx_rs] <= 1'b0;
              tx_busy[ct_r_sel] <= 1'b1;
              out_len_q <= out_len_p[ct_r_sel];
              tx_rs <= ct_r_sel;
              ct_r_sel <= ct_r_sel + 1'd1;
              tx_cnt <= 16'd0;
              tx_rd_idx <= 8'd0;
              tx_blk_v <= 1'b0;
            end else begin
              ts <= TS_IDLE;
              tx_busy[tx_rs] <= 1'b0;
            end
          end else begin
            tx_cnt <= tx_cnt + 16'd1;
            if (tx_b == 4'd15) begin
              tx_blk <= ct_rd_data;
              tx_rd_idx <= tx_rd_idx + 8'd1;
              tx_b <= 4'd0;
            end else begin
              tx_blk <= {tx_blk[119:0], 8'd0};
              tx_b   <= tx_b + 4'd1;
            end
          end
        end
        if (!tx_blk_v && (tx_rd_idx < tx_nct_w[7:0])) begin
          tx_blk <= ct_rd_data;
          tx_rd_idx <= tx_rd_idx + 8'd1;
          tx_blk_v <= 1'b1;
          tx_b <= 4'd0;
        end
      end
      if (ts == TS_IDLE) begin
        m_tvalid_r <= 1'b0;
      end
      ct_rd_data <= ct[(ct_avail[ct_r_sel] && (ts == TS_IDLE ||
                            (ts == TS_TX && tx_cnt == out_len_q - 16'd1))) ?
                            {ct_r_sel, 7'd0} : {tx_rs, tx_rd_idx[6:0]}];
      if (ct_avail[ct_r_sel] && (ts == TS_IDLE)) begin
        ct_avail[ct_r_sel] <= 1'b0;
        tx_busy[ct_r_sel] <= 1'b1;
        out_len_q <= out_len_p[ct_r_sel];
        tx_rs <= ct_r_sel;
        ct_r_sel <= ct_r_sel + 1'd1;
        tx_cnt <= 16'd0;
        tx_rd_idx <= 8'd0;
        tx_blk_v <= 1'b0;
        m_tlast_r <= 1'b0;
        ts <= TS_TX;
      end
      if (key_load) begin
        last_seq_r <= seq_init - 32'd1;
        win_r <= 64'd0;
      end else if (soft_rst) begin
        win_r <= 64'd0;
      end
    end
  end

endmodule
