module spi_regs (
    input wire clk,
    input wire rst_n,

    input  wire [ 6:0] waddr,
    input  wire [31:0] wdata,
    input  wire        wvalid,
    input  wire [ 6:0] raddr,
    input  wire        rreq,
    output wire [31:0] rdata,
    input  wire [31:0] dbg_wan,

    input wire        hsk_rx_wr,
    input wire [31:0] hsk_rx_data,
    input wire        hsk_rx_last,
    input wire [15:0] hsk_rx_len,

    output wire        hsk_tx_valid,
    output wire [31:0] hsk_tx_data,
    output wire        hsk_tx_last,
    output wire [15:0] hsk_tx_len,
    input  wire        hsk_tx_ready,
    output wire        hsk_rx_ready,
    output wire [ 9:0] hsk_rx_room,

    output reg          key_load,
    output wire [255:0] key_enc,
    output wire [255:0] key_dec,
    output wire [ 31:0] cfg_spi,
    output wire [ 95:0] cfg_iv,
    output wire [ 31:0] cfg_src_ip,
    output wire [ 31:0] cfg_dst_ip,
    output wire [ 15:0] cfg_src_port,
    output wire [ 15:0] cfg_dst_port,
    output wire [ 47:0] cfg_src_mac,
    output wire [ 47:0] cfg_dst_mac,
    output wire [ 31:0] cfg_seq,

    input wire        seq_upd,
    input wire [31:0] seq_val,

    input wire [4:0] err_pulse,

    output wire soft_rst
);

  reg [ 31:0] r_spi;
  reg [ 31:0] r_salt_lo;
  reg [ 31:0] r_salt_hi;
  reg [ 31:0] r_src_ip;
  reg [ 31:0] r_dst_ip;
  reg [ 15:0] r_src_port;
  reg [ 15:0] r_dst_port;
  reg [ 31:0] r_src_mac_lo;
  reg [ 15:0] r_src_mac_hi;
  reg [ 31:0] r_dst_mac_lo;
  reg [ 15:0] r_dst_mac_hi;
  reg [ 31:0] r_seq;
  reg [ 7:0] r_scratch;
  reg [255:0] r_key_enc;
  reg [255:0] r_key_dec;
  reg [ 15:0] r_hsk_tx_len;
  reg [ 15:0] len_q        [0:15];
  reg [  3:0] len_wr_ptr;
  reg [  3:0] len_rd_ptr;
  reg [  4:0] len_cnt;
  reg [ 15:0] rx_left;
  reg [  5:0] err_flags;
  reg         soft_rst_r;
  assign soft_rst = soft_rst_r;

  wire [31:0] rx_rd_data;
  reg  [31:0] rx_rd_hold;
  reg  [ 8:0] rx_wr_ptr;
  reg  [ 8:0] rx_rd_ptr;
  reg  [ 9:0] rx_cnt;
  reg  [ 8:0] tx_wr_ptr;
  reg  [ 8:0] tx_rd_ptr;
  reg  [ 9:0] tx_cnt;
  reg  [ 1:0] tx_state;
  reg  [12:0] tx_n;
  reg  [15:0] tx_len_r;
  reg  [15:0] tx_len_lim_r;

  wire [31:0] tx_rd_data;
  reg         hsk_tx_valid_r;
  reg         hsk_tx_last_r;

  localparam TX_IDLE = 2'd0;
  localparam TX_DUMP = 2'd1;

  wire tx_busy = (tx_cnt != 10'd0) || (tx_state == TX_DUMP);
  wire tx_dumping = (tx_state == TX_DUMP);
  wire [15:0] tx_words = {2'd0, tx_len_lim_r[15:2]} + {14'd0, |tx_len_lim_r[1:0]};
  assign hsk_tx_len = tx_len_lim_r;
  wire [ 3:0] nxt_ptr = len_rd_ptr + 4'd1;
  wire        len_push = hsk_rx_last && (len_cnt != 5'd16);
  wire        rd_pop = rreq && (raddr == 7'h38) && (rx_cnt != 13'd0);
  wire        pop_last = rd_pop && (rx_left <= 16'd1);
  wire [15:0] push_words = {2'd0, hsk_rx_len[15:2]} + {14'd0, |hsk_rx_len[1:0]};
  wire [15:0] nxt_len = (len_push && (len_wr_ptr == nxt_ptr)) ? hsk_rx_len : len_q[nxt_ptr];
  wire [15:0] nxt_words = {2'd0, nxt_len[15:2]} + {14'd0, |nxt_len[1:0]};
  wire        left_load = (len_push && (len_cnt == 5'd0)) || pop_last;
  wire [15:0] left_val = (len_push && (len_cnt == 5'd0)) ? push_words : nxt_words;
  wire        hsk_rx_pending = (len_cnt != 5'd0);

  assign hsk_rx_ready = (rx_cnt != 10'd512) && (len_cnt != 5'd16);
  assign hsk_rx_room = 10'd512 - rx_cnt[9:0];
  assign hsk_tx_data = tx_rd_data;
  assign hsk_tx_valid = hsk_tx_valid_r;
  assign hsk_tx_last = hsk_tx_last_r;
  assign key_enc = r_key_enc;
  assign key_dec = r_key_dec;
  assign cfg_spi = r_spi;
  assign cfg_iv = {r_salt_hi, r_salt_lo, 32'd0};
  assign cfg_src_ip = r_src_ip;
  assign cfg_dst_ip = r_dst_ip;
  assign cfg_src_port = r_src_port;
  assign cfg_dst_port = r_dst_port;
  assign cfg_src_mac = {r_src_mac_hi, r_src_mac_lo};
  assign cfg_dst_mac = {r_dst_mac_hi, r_dst_mac_lo};
  assign cfg_seq = r_seq;

  bram_32x512 u_rx_fifo (
      .clk(clk),
      .waddr(rx_wr_ptr[8:0]),
      .wdata(hsk_rx_data),
      .we(hsk_rx_wr),
      .raddr(rx_rd_ptr[8:0]),
      .rdata(rx_rd_data)
  );
  bram_32x512 u_tx_fifo (
      .clk(clk),
      .waddr(tx_wr_ptr[8:0]),
      .wdata(wdata),
      .we(wvalid && (waddr == 7'h40) && !tx_dumping && (tx_cnt != 10'd512)),
      .raddr(tx_rd_ptr[8:0]),
      .rdata(tx_rd_data)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_spi <= 32'd0;
      r_salt_lo <= 32'd0;
      r_salt_hi <= 32'd0;
      r_src_ip <= 32'd0;
      r_dst_ip <= 32'd0;
      r_src_port <= 16'd0;
      r_dst_port <= 16'd0;
      r_src_mac_lo <= 32'd0;
      r_src_mac_hi <= 16'd0;
      r_dst_mac_lo <= 32'd0;
      r_dst_mac_hi <= 16'd0;
      r_key_enc <= 256'd0;
      r_key_dec <= 256'd0;
      r_hsk_tx_len <= 16'd0;
      len_wr_ptr <= 4'd0;
      len_rd_ptr <= 4'd0;
      len_cnt <= 5'd0;
      rx_left <= 16'd0;
      rx_rd_hold <= 32'd0;
      key_load <= 1'b0;
      r_seq <= 32'd1;
      r_scratch <= 8'd0;
      err_flags <= 6'd0;
      soft_rst_r <= 1'b0;
      rx_wr_ptr <= 9'd0;
      rx_rd_ptr <= 9'd0;
      rx_cnt <= 10'd0;
      tx_wr_ptr <= 9'd0;
      tx_rd_ptr <= 9'd0;
      tx_cnt <= 10'd0;
      tx_state <= TX_IDLE;
      tx_n <= 13'd0;
      tx_len_r <= 16'd0;
      tx_len_lim_r <= 16'd0;
      hsk_tx_valid_r <= 1'b0;
      hsk_tx_last_r <= 1'b0;
    end else begin
      key_load   <= 1'b0;
      soft_rst_r <= 1'b0;
      if (tx_state == TX_DUMP && tx_n < tx_words) begin
        hsk_tx_valid_r <= 1'b1;
        hsk_tx_last_r  <= (tx_n == (tx_words - 16'd1));
      end else begin
        hsk_tx_valid_r <= 1'b0;
        hsk_tx_last_r  <= 1'b0;
      end
      if (wvalid) begin
        case (waddr)
          7'h00: begin
            if (wdata[0]) key_load <= 1'b1;
            if (wdata[2]) soft_rst_r <= 1'b1;
            if (wdata[1] && !tx_dumping) begin
              tx_state <= TX_DUMP;
              tx_n <= 13'd0;
              tx_len_r <= r_hsk_tx_len;
              tx_len_lim_r <=
                  (r_hsk_tx_len > {4'd0, tx_cnt, 2'b00})
                  ? {4'd0, tx_cnt, 2'b00}
                  : r_hsk_tx_len;
            end
          end
          7'h08:   r_spi <= wdata;
          7'h0C:   r_salt_lo <= wdata;
          7'h10:   r_salt_hi <= wdata;
          7'h14:   r_src_ip <= wdata;
          7'h18:   r_dst_ip <= wdata;
          7'h1C:   r_src_port <= wdata[15:0];
          7'h20:   r_dst_port <= wdata[15:0];
          7'h24:   r_src_mac_lo <= wdata;
          7'h28:   r_src_mac_hi <= wdata[15:0];
          7'h2C:   r_dst_mac_lo <= wdata;
          7'h30:   r_dst_mac_hi <= wdata[15:0];
          7'h74:   r_seq <= wdata;
          7'h78:   r_scratch <= wdata[7:0];
          7'h3C:   if (!tx_dumping) r_hsk_tx_len <= wdata[15:0];
          7'h40: begin
            if (tx_cnt != 10'd512) begin
              tx_wr_ptr <= tx_wr_ptr + 9'd1;
              tx_cnt <= tx_cnt + 10'd1;
            end else begin
              err_flags[5] <= 1'b1;
            end
          end
          7'h50:   err_flags <= 6'd0;
          7'h44:   r_key_enc[255:224] <= wdata;
          7'h45:   r_key_enc[223:192] <= wdata;
          7'h46:   r_key_enc[191:160] <= wdata;
          7'h47:   r_key_enc[159:128] <= wdata;
          7'h48:   r_key_enc[127:96] <= wdata;
          7'h49:   r_key_enc[95:64] <= wdata;
          7'h4A:   r_key_enc[63:32] <= wdata;
          7'h4B:   r_key_enc[31:0] <= wdata;
          7'h64:   r_key_dec[255:224] <= wdata;
          7'h65:   r_key_dec[223:192] <= wdata;
          7'h66:   r_key_dec[191:160] <= wdata;
          7'h67:   r_key_dec[159:128] <= wdata;
          7'h68:   r_key_dec[127:96] <= wdata;
          7'h69:   r_key_dec[95:64] <= wdata;
          7'h6A:   r_key_dec[63:32] <= wdata;
          7'h6B:   r_key_dec[31:0] <= wdata;
          default: ;
        endcase
      end
      if (rd_pop) begin
        rx_rd_ptr <= rx_rd_ptr + 9'd1;
        rx_cnt    <= rx_cnt - 10'd1;
      end
      if (rreq && (raddr == 7'h38)) rx_rd_hold <= rx_rd_data;
      if (hsk_rx_wr) begin
        rx_wr_ptr <= rx_wr_ptr + 9'd1;
        rx_cnt    <= rx_cnt + 10'd1;
      end
      if (len_push) begin
        len_q[len_wr_ptr] <= hsk_rx_len;
        len_wr_ptr <= len_wr_ptr + 4'd1;
      end
      len_cnt <= len_cnt + (len_push ? 5'd1 : 5'd0) - (pop_last ? 5'd1 : 5'd0);
      if (pop_last) len_rd_ptr <= len_rd_ptr + 4'd1;
      if (left_load) rx_left <= left_val;
      else if (rd_pop) rx_left <= rx_left - 16'd1;
      if (seq_upd) r_seq <= seq_val;
      if (err_pulse[0]) err_flags[0] <= 1'b1;
      if (err_pulse[1]) err_flags[1] <= 1'b1;
      if (err_pulse[2]) err_flags[2] <= 1'b1;
      if (err_pulse[3]) err_flags[3] <= 1'b1;
      if (err_pulse[4]) err_flags[4] <= 1'b1;
      if (soft_rst_r) begin
        err_flags <= 6'd0;
        rx_wr_ptr <= 9'd0;
        rx_rd_ptr <= 9'd0;
        rx_cnt <= 10'd0;
        len_wr_ptr <= 4'd0;
        len_rd_ptr <= 4'd0;
        len_cnt <= 5'd0;
        rx_left <= 16'd0;
        tx_wr_ptr <= 9'd0;
        tx_rd_ptr <= 9'd0;
        tx_cnt <= 10'd0;
        tx_state <= TX_IDLE;
        tx_n <= 13'd0;
        tx_len_r <= 16'd0;
        tx_len_lim_r <= 16'd0;
      end else begin
        case (tx_state)
          TX_DUMP: begin
            if (tx_n >= tx_words) begin
              tx_state <= TX_IDLE;
              tx_n <= 13'd0;
              tx_cnt <= 10'd0;
            end else if (hsk_tx_ready) begin
              tx_rd_ptr <= tx_rd_ptr + 9'd1;
              tx_cnt <= tx_cnt - 10'd1;
              if (tx_n == tx_words - 13'd1) begin
                tx_state <= TX_IDLE;
                tx_n <= 13'd0;
                tx_cnt <= 10'd0;
              end else begin
                tx_n <= tx_n + 13'd1;
              end
            end
          end
          default: ;
        endcase
      end
    end
  end

  reg [31:0] rdata_c;
  always @* begin
    rdata_c = 32'd0;
    case (raddr)
      7'h04:   rdata_c = {28'd0, tx_busy, hsk_rx_pending};
      7'h34:   rdata_c = {16'd0, (len_cnt != 5'd0) ? len_q[len_rd_ptr] : 16'd0};
      7'h38:   rdata_c = rx_rd_hold;
      7'h50:   rdata_c = {26'd0, err_flags};
      7'h74:   rdata_c = r_seq;
      7'h78:   rdata_c = {24'd0, r_scratch};
      7'h70:   rdata_c = dbg_wan;
      default: rdata_c = 32'd0;
    endcase
  end
  assign rdata = rdata_c;

endmodule
