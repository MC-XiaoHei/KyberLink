module self_test_port #(
    parameter [47:0] LOCAL_MAC = 48'h02_00_00_00_00_01,
    parameter [47:0] PEER_MAC  = 48'h02_00_00_00_00_02
) (
    input wire clk,
    input wire rst_n,

    input wire enable,
    input wire loopback,
    input wire clear,

    output wire [7:0] tx_tdata,
    output wire       tx_tvalid,
    output wire       tx_tlast,
    input  wire       tx_tready,

    input  wire [7:0] rx_tdata,
    input  wire       rx_tvalid,
    input  wire       rx_tlast,
    input  wire       rx_tuser,
    output wire       rx_tready,

    output reg [31:0] stat_tx,
    output reg [31:0] stat_rx_good,
    output reg [31:0] stat_rx_bad,
    output reg [31:0] stat_rx_diff,
    output reg [31:0] stat_seq_tx,
    output reg [31:0] stat_seq_rx
);

  wire gen_ready = loopback ? 1'b1 : tx_tready;

  reg [5:0] tx_pos;
  reg tx_busy;
  reg [31:0] tx_seq;
  reg [31:0] tx_lfsr;
  reg [7:0] tx_byte;

  wire [5:0] tx_nxt = (tx_pos == 6'd63) ? 6'd0 : tx_pos + 6'd1;

  wire [31:0] tx_x1 = tx_lfsr ^ {tx_lfsr[18:0], 13'd0};
  wire [31:0] tx_x2 = tx_x1 ^ {17'd0, tx_x1[31:17]};
  wire [31:0] tx_x3 = tx_x2 ^ {tx_x2[26:0], 5'd0};

  wire [31:0] tx_lfsr_nxt = (tx_nxt == 6'd18) ? (tx_seq | 32'd1) : tx_x3;

  wire [ 7:0] nxt_dst = (tx_nxt == 6'd0) ? PEER_MAC[47:40] :
                        (tx_nxt == 6'd1) ? PEER_MAC[39:32] :
                        (tx_nxt == 6'd2) ? PEER_MAC[31:24] :
                        (tx_nxt == 6'd3) ? PEER_MAC[23:16] :
                        (tx_nxt == 6'd4) ? PEER_MAC[15:8] :
                        PEER_MAC[7:0];

  wire [ 7:0] nxt_src = (tx_nxt == 6'd6) ? LOCAL_MAC[47:40] :
                        (tx_nxt == 6'd7) ? LOCAL_MAC[39:32] :
                        (tx_nxt == 6'd8) ? LOCAL_MAC[31:24] :
                        (tx_nxt == 6'd9) ? LOCAL_MAC[23:16] :
                        (tx_nxt == 6'd10) ? LOCAL_MAC[15:8] :
                        LOCAL_MAC[7:0];

  wire [ 7:0] nxt_seq = (tx_nxt == 6'd14) ? tx_seq[31:24] :
                        (tx_nxt == 6'd15) ? tx_seq[23:16] :
                        (tx_nxt == 6'd16) ? tx_seq[15:8] :
                        tx_seq[7:0];

  wire [ 7:0] tx_byte_nxt = (tx_nxt < 6'd6) ? nxt_dst :
                            (tx_nxt < 6'd12) ? nxt_src :
                            (tx_nxt == 6'd12) ? 8'h88 :
                            (tx_nxt == 6'd13) ? 8'hb5 :
                            (tx_nxt < 6'd18) ? nxt_seq :
                            tx_lfsr_nxt[7:0];

  assign tx_tdata  = tx_byte;
  assign tx_tvalid = tx_busy && !loopback;
  assign tx_tlast  = tx_busy && (tx_pos == 6'd63);
  assign rx_tready = 1'b1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_pos  <= 6'd0;
      tx_busy <= 1'b0;
      tx_seq  <= 32'd0;
      tx_lfsr <= 32'd0;
      tx_byte <= 8'd0;
      stat_tx <= 32'd0;
    end else if (clear) begin
      tx_pos  <= 6'd0;
      tx_busy <= 1'b0;
      tx_seq  <= 32'd0;
      tx_lfsr <= 32'd0;
      tx_byte <= 8'd0;
      stat_tx <= 32'd0;
    end else if (tx_busy) begin
      if (gen_ready) begin
        if (tx_pos == 6'd63) begin
          tx_busy <= 1'b0;
          tx_pos  <= 6'd0;
          tx_seq  <= tx_seq + 32'd1;
          stat_tx <= stat_tx + 32'd1;
        end else begin
          tx_pos  <= tx_nxt;
          tx_lfsr <= tx_lfsr_nxt;
          tx_byte <= tx_byte_nxt;
        end
      end
    end else if (enable) begin
      tx_busy <= 1'b1;
      tx_pos  <= 6'd0;
      tx_lfsr <= tx_seq | 32'd1;
      tx_byte <= PEER_MAC[47:40];
    end
  end

  wire [7:0] chk_tdata = loopback ? tx_byte : rx_tdata;
  wire chk_tvalid = loopback ? tx_busy : rx_tvalid;
  wire chk_tlast = loopback ? tx_tlast : rx_tlast;
  wire chk_tuser = loopback ? 1'b0 : rx_tuser;

  reg [5:0] rx_pos;
  reg rx_diff;
  reg [31:0] rx_seq;
  reg [31:0] rx_lfsr;

  wire [31:0] rx_x1 = rx_lfsr ^ {rx_lfsr[18:0], 13'd0};
  wire [31:0] rx_x2 = rx_x1 ^ {17'd0, rx_x1[31:17]};
  wire [31:0] rx_x3 = rx_x2 ^ {rx_x2[26:0], 5'd0};

  wire [ 7:0] exp_dst_b = (rx_pos == 6'd1) ? LOCAL_MAC[39:32] :
                          (rx_pos == 6'd2) ? LOCAL_MAC[31:24] :
                          (rx_pos == 6'd3) ? LOCAL_MAC[23:16] :
                          (rx_pos == 6'd4) ? LOCAL_MAC[15:8] :
                          (rx_pos == 6'd5) ? LOCAL_MAC[7:0] :
                          LOCAL_MAC[47:40];

  wire [ 7:0] exp_src_b = (rx_pos == 6'd7) ? PEER_MAC[39:32] :
                          (rx_pos == 6'd8) ? PEER_MAC[31:24] :
                          (rx_pos == 6'd9) ? PEER_MAC[23:16] :
                          (rx_pos == 6'd10) ? PEER_MAC[15:8] :
                          (rx_pos == 6'd11) ? PEER_MAC[7:0] :
                          PEER_MAC[47:40];

  wire hdr_ok = loopback ? 1'b1 :
                (rx_pos < 6'd6) ? (chk_tdata == exp_dst_b) :
                (rx_pos < 6'd12) ? (chk_tdata == exp_src_b) :
                (rx_pos == 6'd12) ? (chk_tdata == 8'h88) :
                (rx_pos == 6'd13) ? (chk_tdata == 8'hb5) : 1'b1;

  wire pay_ok = (rx_pos < 6'd18) ? 1'b1 : (chk_tdata == rx_lfsr[7:0]);
  wire byte_ok = hdr_ok && pay_ok;
  wire [31:0] seq_full = {rx_seq[23:0], chk_tdata};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_pos <= 6'd0;
      rx_diff <= 1'b0;
      rx_seq <= 32'd0;
      rx_lfsr <= 32'd0;
      stat_rx_good <= 32'd0;
      stat_rx_bad <= 32'd0;
      stat_rx_diff <= 32'd0;
      stat_seq_tx <= 32'd0;
      stat_seq_rx <= 32'd0;
    end else if (clear) begin
      rx_pos <= 6'd0;
      rx_diff <= 1'b0;
      rx_seq <= 32'd0;
      rx_lfsr <= 32'd0;
      stat_rx_good <= 32'd0;
      stat_rx_bad <= 32'd0;
      stat_rx_diff <= 32'd0;
      stat_seq_tx <= 32'd0;
      stat_seq_rx <= 32'd0;
    end else begin
      stat_seq_tx <= tx_seq;
      if (chk_tvalid) begin
        if (rx_pos == 6'd0) begin
          rx_diff <= 1'b0;
          rx_seq  <= 32'd0;
          rx_lfsr <= 32'd0;
        end
        if (rx_pos >= 6'd14 && rx_pos < 6'd18) rx_seq <= {rx_seq[23:0], chk_tdata};
        if (rx_pos == 6'd17) rx_lfsr <= seq_full | 32'd1;
        else if (rx_pos >= 6'd18) rx_lfsr <= rx_x3;
        if (!byte_ok) begin
          rx_diff <= 1'b1;
          stat_rx_diff <= stat_rx_diff + 32'd1;
        end
        if (chk_tlast) begin
          stat_seq_rx <= (rx_pos == 6'd17) ? (seq_full | 32'd1) : rx_seq;
          if (chk_tuser || rx_diff || !byte_ok) stat_rx_bad <= stat_rx_bad + 32'd1;
          else stat_rx_good <= stat_rx_good + 32'd1;
        end
        if (rx_pos == 6'd63) rx_pos <= 6'd0;
        else rx_pos <= rx_pos + 6'd1;
      end
    end
  end

endmodule
