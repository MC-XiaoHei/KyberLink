module spi_regs (
    input wire clk,
    input wire rst_n,

    input  wire [ 6:0] waddr,
    input  wire [31:0] wdata,
    input  wire        wvalid,
    input  wire [ 6:0] raddr,
    input  wire        rreq,
    output wire [31:0] rdata,

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

    output reg         key_load,
    output reg [255:0] key_enc,
    output reg [255:0] key_dec,
    output reg [ 31:0] cfg_spi,
    output reg [ 95:0] cfg_iv,
    output reg [ 31:0] cfg_src_ip,
    output reg [ 31:0] cfg_dst_ip,
    output reg [ 15:0] cfg_src_port,
    output reg [ 15:0] cfg_dst_port,
    output reg [ 47:0] cfg_src_mac,
    output reg [ 47:0] cfg_dst_mac,
    output reg [ 31:0] cfg_seq,

    input wire        seq_upd,
    input wire [31:0] seq_val,

    input  wire err_badtag_i,
    input  wire err_badpad_i,
    input  wire err_replay_i,
    input  wire err_oversize_i,
    input  wire err_rxdrop_i,
    output wire soft_rst
);

  reg [ 31:0] r_ctrl;
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
  reg [255:0] r_key_enc;
  reg [255:0] r_key_dec;
  reg [ 15:0] r_hsk_tx_len;
  reg [ 15:0] r_hsk_rx_len;
  reg         hsk_rx_pending;

  reg [31:0] cnt_badtag;
  reg [31:0] cnt_badpad;
  reg [31:0] cnt_replay;
  reg [31:0] cnt_oversize;
  reg [31:0] cnt_rxdrop;
  reg        soft_rst_r;
  assign soft_rst = soft_rst_r;

  (* syn_ramstyle = "block_ram" *)reg [ 31:0] rx_fifo        [0:2047];
  (* syn_ramstyle = "block_ram" *)reg [ 31:0] tx_fifo        [0:2047];
  reg [ 31:0] rx_rd_data;
  reg [ 11:0] rx_wr_ptr;
  reg [ 11:0] rx_rd_ptr;
  reg [ 12:0] rx_cnt;
  reg [ 11:0] tx_wr_ptr;
  reg [ 11:0] tx_rd_ptr;
  reg [ 12:0] tx_cnt;
  reg [  1:0] tx_state;
  reg [ 12:0] tx_n;
  reg [ 15:0] tx_len_r;
  reg         last_hold;

  localparam TX_IDLE = 2'd0;
  localparam TX_DUMP = 2'd1;

  wire [15:0] tx_words = {2'd0, tx_len_r[15:2]} + {14'd0, |tx_len_r[1:0]};
  assign hsk_tx_len   = tx_len_r;
  assign hsk_rx_ready = (rx_cnt != 13'd2048);
  assign hsk_tx_data  = tx_fifo[tx_rd_ptr[11:0]];
  assign hsk_tx_valid = (tx_state == TX_DUMP) && (tx_n < tx_words);
  assign hsk_tx_last  = (tx_state == TX_DUMP) && (tx_n == (tx_words - 16'd1));

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      r_ctrl <= 32'd0;
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
      r_hsk_rx_len <= 16'd0;
      hsk_rx_pending <= 1'b0;
      key_load <= 1'b0;
      key_enc <= 256'd0;
      key_dec <= 256'd0;
      cfg_spi <= 32'd0;
      cfg_iv <= 96'd0;
      cfg_src_ip <= 32'd0;
      cfg_dst_ip <= 32'd0;
      cfg_src_port <= 16'd0;
      cfg_dst_port <= 16'd0;
      cfg_src_mac <= 48'd0;
      cfg_dst_mac <= 48'd0;
      cfg_seq <= 32'd1;
      r_seq <= 32'd1;
      cnt_badtag <= 32'd0;
      cnt_badpad <= 32'd0;
      cnt_replay <= 32'd0;
      cnt_oversize <= 32'd0;
      cnt_rxdrop <= 32'd0;
      soft_rst_r <= 1'b0;
      rx_wr_ptr <= 11'd0;
      rx_rd_ptr <= 11'd0;
      rd_q <= 11'd0;
      rx_rd_data <= 32'd0;
      rx_cnt <= 12'd0;
      tx_wr_ptr <= 11'd0;
      tx_rd_ptr <= 11'd0;
      tx_cnt <= 12'd0;
      tx_state <= TX_IDLE;
      tx_n <= 12'd0;
      tx_len_r <= 16'd0;
    end else begin
      key_load <= 1'b0;
      soft_rst_r <= 1'b0;
      if (wvalid) begin
        case (waddr)
          7'h00: begin
            r_ctrl <= wdata;
            if (wdata[0]) key_load <= 1'b1;
            if (wdata[2]) soft_rst_r <= 1'b1;
            if (wdata[1]) begin
              tx_state <= TX_DUMP;
              tx_n <= 12'd0;
              tx_len_r <= r_hsk_tx_len;
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
          7'h3C:   r_hsk_tx_len <= wdata[15:0];
          7'h40: begin
            tx_fifo[tx_wr_ptr] <= wdata;
            tx_wr_ptr <= tx_wr_ptr + 11'd1;
            tx_cnt <= tx_cnt + 12'd1;
          end
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
      rd_q <= rx_rd_ptr;
      rx_rd_data <= rx_fifo[rd_q];
      if (rreq && (raddr == 7'h38) && (rx_cnt != 12'd0)) begin
        rx_rd_ptr <= rx_rd_ptr + 11'd1;
        rx_cnt <= rx_cnt - 12'd1;
      end
      if (hsk_rx_wr) begin
        rx_fifo[rx_wr_ptr] <= hsk_rx_data;
        rx_wr_ptr <= rx_wr_ptr + 11'd1;
        rx_cnt <= rx_cnt + 12'd1;
      end
      if (hsk_rx_last) begin
        r_hsk_rx_len   <= hsk_rx_len;
        hsk_rx_pending <= 1'b1;
      end
      if (seq_upd) r_seq <= seq_val;
      if (rx_cnt == 12'd0) hsk_rx_pending <= 1'b0;
      if (soft_rst_r) begin
        cnt_badtag <= 32'd0;
        cnt_badpad <= 32'd0;
        cnt_replay <= 32'd0;
        cnt_oversize <= 32'd0;
        cnt_rxdrop <= 32'd0;
        rx_wr_ptr <= 11'd0;
        rx_rd_ptr <= 11'd0;
        rd_q <= 11'd0;
        rx_cnt <= 12'd0;
        rx_rd_data <= 32'd0;
        hsk_rx_pending <= 1'b0;
        tx_wr_ptr <= 11'd0;
        tx_rd_ptr <= 11'd0;
        tx_cnt <= 12'd0;
        tx_state <= TX_IDLE;
        tx_n <= 12'd0;
        tx_len_r <= 16'd0;
      end else begin
        if (err_badtag_i && (cnt_badtag != 32'hFFFFFFFF))
          cnt_badtag <= cnt_badtag + 32'd1;
        if (err_badpad_i && (cnt_badpad != 32'hFFFFFFFF))
          cnt_badpad <= cnt_badpad + 32'd1;
        if (err_replay_i && (cnt_replay != 32'hFFFFFFFF))
          cnt_replay <= cnt_replay + 32'd1;
        if (err_oversize_i && (cnt_oversize != 32'hFFFFFFFF))
          cnt_oversize <= cnt_oversize + 32'd1;
        if (err_rxdrop_i && (cnt_rxdrop != 32'hFFFFFFFF))
          cnt_rxdrop <= cnt_rxdrop + 32'd1;
      end
      if (key_load) begin
        key_enc <= r_key_enc;
        key_dec <= r_key_dec;
        cfg_spi <= r_spi;
        cfg_iv <= {r_salt_hi, r_salt_lo, 32'd0};
        cfg_src_ip <= r_src_ip;
        cfg_dst_ip <= r_dst_ip;
        cfg_src_port <= r_src_port;
        cfg_dst_port <= r_dst_port;
        cfg_src_mac <= {r_src_mac_hi, r_src_mac_lo};
        cfg_dst_mac <= {r_dst_mac_hi, r_dst_mac_lo};
        cfg_seq <= r_seq;
      end
      case (tx_state)
        TX_DUMP: begin
          if (hsk_tx_ready && hsk_tx_valid && tx_n < tx_words) begin
            tx_rd_ptr <= tx_rd_ptr + 11'd1;
            tx_cnt <= tx_cnt - 12'd1;
            if (tx_n == tx_words - 13'd1) begin
              tx_state <= TX_IDLE;
              tx_n <= 12'd0;
            end else begin
              tx_n <= tx_n + 12'd1;
            end
          end
        end
        default: ;
      endcase
    end
  end

  reg [11:0] rd_q;
  reg [31:0] rdata_c;
  always @* begin
    rdata_c = 32'd0;
    case (raddr)
      7'h00:   rdata_c = r_ctrl;
      7'h04:   rdata_c = {16'd0, hsk_rx_pending ? 16'h0001 : 16'h0000};
      7'h08:   rdata_c = r_spi;
      7'h0C:   rdata_c = r_salt_lo;
      7'h10:   rdata_c = r_salt_hi;
      7'h14:   rdata_c = r_src_ip;
      7'h18:   rdata_c = r_dst_ip;
      7'h1C:   rdata_c = {16'd0, r_src_port};
      7'h20:   rdata_c = {16'd0, r_dst_port};
      7'h24:   rdata_c = r_src_mac_lo;
      7'h28:   rdata_c = {16'd0, r_src_mac_hi};
      7'h2C:   rdata_c = r_dst_mac_lo;
      7'h30:   rdata_c = {16'd0, r_dst_mac_hi};
      7'h34:   rdata_c = {16'd0, r_hsk_rx_len};
      7'h74:   rdata_c = r_seq;
      7'h50:   rdata_c = cnt_badtag;
      7'h54:   rdata_c = cnt_badpad;
      7'h58:   rdata_c = cnt_replay;
      7'h5C:   rdata_c = cnt_oversize;
      7'h60:   rdata_c = cnt_rxdrop;
      7'h38:   rdata_c = rx_rd_data;
      7'h3C:   rdata_c = {16'd0, r_hsk_tx_len};
      7'h44:   rdata_c = r_key_enc[255:224];
      7'h45:   rdata_c = r_key_enc[223:192];
      7'h46:   rdata_c = r_key_enc[191:160];
      7'h47:   rdata_c = r_key_enc[159:128];
      7'h48:   rdata_c = r_key_enc[127:96];
      7'h49:   rdata_c = r_key_enc[95:64];
      7'h4A:   rdata_c = r_key_enc[63:32];
      7'h4B:   rdata_c = r_key_enc[31:0];
      7'h64:   rdata_c = r_key_dec[255:224];
      7'h65:   rdata_c = r_key_dec[223:192];
      7'h66:   rdata_c = r_key_dec[191:160];
      7'h67:   rdata_c = r_key_dec[159:128];
      7'h68:   rdata_c = r_key_dec[127:96];
      7'h69:   rdata_c = r_key_dec[95:64];
      7'h6A:   rdata_c = r_key_dec[63:32];
      7'h6B:   rdata_c = r_key_dec[31:0];
      default: rdata_c = 32'd0;
    endcase
  end
  assign rdata = rdata_c;

endmodule
