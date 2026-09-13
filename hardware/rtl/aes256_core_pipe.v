module aes256_core_pipe (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         key_load,
    input  wire         start,
    input  wire [255:0] key,
    input  wire [127:0] block_in,
    input  wire         blk_valid,
    output wire         busy,
    output wire         crypt_rdy,
    output wire         load_rdy,
    output wire         done,
    output wire [127:0] block_out
);
  localparam PHASE_IDLE     = 3'd0;
  localparam PHASE_KEYEXP_A = 3'd1;
  localparam PHASE_KEYEXP_B = 3'd2;
  localparam PHASE_CRYPT    = 3'd3;

  reg [2:0] phase;
  reg [3:0] rke;
  reg [127:0] k0_r;
  reg [127:0] k1_r;
  reg ax_loaded;

  function [7:0] gmul2(input [7:0] x);
    gmul2 = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
  endfunction

  function [7:0] gmul3(input [7:0] x);
    gmul3 = gmul2(x) ^ x;
  endfunction

  reg [127:0] st_prev;
  reg [127:0] st_prev2;
  wire [31:0] wm1 = st_prev[31:0];
  wire [31:0] w8 = st_prev2[127:96];
  wire [7:0]  rcon = rke[0] ? 8'h00 :
                       (rke >> 1) == 4'd1 ? 8'h01 :
                       (rke >> 1) == 4'd2 ? 8'h02 :
                       (rke >> 1) == 4'd3 ? 8'h04 :
                       (rke >> 1) == 4'd4 ? 8'h08 :
                       (rke >> 1) == 4'd5 ? 8'h10 :
                       (rke >> 1) == 4'd6 ? 8'h20 : 8'h40;

  wire [7:0] sb0_c, sb1_c, sb2_c, sb3_c;
  sbox_combo_cf_lut u_sb_k0 (
      .x(wm1[31:24]),
      .y(sb0_c)
  );
  sbox_combo_cf_lut u_sb_k1 (
      .x(wm1[23:16]),
      .y(sb1_c)
  );
  sbox_combo_cf_lut u_sb_k2 (
      .x(wm1[15:8]),
      .y(sb2_c)
  );
  sbox_combo_cf_lut u_sb_k3 (
      .x(wm1[7:0]),
      .y(sb3_c)
  );

  reg [7:0] sb0_r, sb1_r, sb2_r, sb3_r;
  always @(posedge clk) begin
    sb0_r <= sb0_c;
    sb1_r <= sb1_c;
    sb2_r <= sb2_c;
    sb3_r <= sb3_c;
  end

  wire [31:0] temp = rke[0]
        ? {sb0_r, sb1_r, sb2_r, sb3_r}
        : {sb1_r, sb2_r, sb3_r, sb0_r} ^ {rcon, 24'd0};
  wire [31:0] we0 = w8 ^ temp;
  wire [31:0] we1 = st_prev2[95:64] ^ we0;
  wire [31:0] we2 = st_prev2[63:32] ^ we1;
  wire [31:0] we3 = st_prev2[31:0] ^ we2;

  reg [127:0] state[0:2];
  // 读索引 b1_d 恒为上一拍写入的槽位，三槽数组退化成这一级流水
  reg [127:0] sbox_c_d;
  reg [3:0] rd[0:2];
  reg [1:0] blk_sel;
  reg [1:0] blk_sel_d;
  reg [127:0] out_r;
  reg done_q;
  reg crypt_rdy_q;

  wire [1:0] b1 = (blk_sel == 2'd0) ? 2'd2 : blk_sel - 2'd1;
  wire [1:0] b2 = (blk_sel == 2'd2) ? 2'd0 : (blk_sel == 2'd1) ? 2'd2 : 2'd1;
  // 选择信号提前一拍译码，避免该 LUT 落在读通路上
  reg [1:0] b1_d;

  wire [127:0] sbox_c;
  wire [127:0] sr_in = {
    state[blk_sel][127:120],
    state[blk_sel][87:80],
    state[blk_sel][47:40],
    state[blk_sel][7:0],
    state[blk_sel][95:88],
    state[blk_sel][55:48],
    state[blk_sel][15:8],
    state[blk_sel][103:96],
    state[blk_sel][63:56],
    state[blk_sel][23:16],
    state[blk_sel][111:104],
    state[blk_sel][71:64],
    state[blk_sel][31:24],
    state[blk_sel][119:112],
    state[blk_sel][79:72],
    state[blk_sel][39:32]
  };
  sb_sbox16 u_sb (
      .clk(clk),
      .x  (sr_in),
      .y  (sbox_c)
  );

  wire [7:0] m0 = sbox_c_d[127:120];
  wire [7:0] m1 = sbox_c_d[119:112];
  wire [7:0] m2 = sbox_c_d[111:104];
  wire [7:0] m3 = sbox_c_d[103:96];
  wire [7:0] m4 = sbox_c_d[95:88];
  wire [7:0] m5 = sbox_c_d[87:80];
  wire [7:0] m6 = sbox_c_d[79:72];
  wire [7:0] m7 = sbox_c_d[71:64];
  wire [7:0] m8 = sbox_c_d[63:56];
  wire [7:0] m9 = sbox_c_d[55:48];
  wire [7:0] m10 = sbox_c_d[47:40];
  wire [7:0] m11 = sbox_c_d[39:32];
  wire [7:0] m12 = sbox_c_d[31:24];
  wire [7:0] m13 = sbox_c_d[23:16];
  wire [7:0] m14 = sbox_c_d[15:8];
  wire [7:0] m15 = sbox_c_d[7:0];

  wire [7:0] mc_col0[3:0];
  wire [7:0] mc_col1[3:0];
  wire [7:0] mc_col2[3:0];
  wire [7:0] mc_col3[3:0];
  assign mc_col0[0] = gmul2(m0) ^ gmul3(m1) ^ m2 ^ m3;
  assign mc_col0[1] = m0 ^ gmul2(m1) ^ gmul3(m2) ^ m3;
  assign mc_col0[2] = m0 ^ m1 ^ gmul2(m2) ^ gmul3(m3);
  assign mc_col0[3] = gmul3(m0) ^ m1 ^ m2 ^ gmul2(m3);
  assign mc_col1[0] = gmul2(m4) ^ gmul3(m5) ^ m6 ^ m7;
  assign mc_col1[1] = m4 ^ gmul2(m5) ^ gmul3(m6) ^ m7;
  assign mc_col1[2] = m4 ^ m5 ^ gmul2(m6) ^ gmul3(m7);
  assign mc_col1[3] = gmul3(m4) ^ m5 ^ m6 ^ gmul2(m7);
  assign mc_col2[0] = gmul2(m8) ^ gmul3(m9) ^ m10 ^ m11;
  assign mc_col2[1] = m8 ^ gmul2(m9) ^ gmul3(m10) ^ m11;
  assign mc_col2[2] = m8 ^ m9 ^ gmul2(m10) ^ gmul3(m11);
  assign mc_col2[3] = gmul3(m8) ^ m9 ^ m10 ^ gmul2(m11);
  assign mc_col3[0] = gmul2(m12) ^ gmul3(m13) ^ m14 ^ m15;
  assign mc_col3[1] = m12 ^ gmul2(m13) ^ gmul3(m14) ^ m15;
  assign mc_col3[2] = m12 ^ m13 ^ gmul2(m14) ^ gmul3(m15);
  assign mc_col3[3] = gmul3(m12) ^ m13 ^ m14 ^ gmul2(m15);

  wire [127:0] mc_comb = {
    mc_col0[0],
    mc_col0[1],
    mc_col0[2],
    mc_col0[3],
    mc_col1[0],
    mc_col1[1],
    mc_col1[2],
    mc_col1[3],
    mc_col2[0],
    mc_col2[1],
    mc_col2[2],
    mc_col2[3],
    mc_col3[0],
    mc_col3[1],
    mc_col3[2],
    mc_col3[3]
  };

  wire [127:0] mid_cmb = (rd[b1_d] == 4'd14) ? sbox_c_d : mc_comb;
  wire [127:0] state_next = mid_cmb ^ ksch_q;
  assign block_out = out_r;

  wire [127:0] ksch_q;
  wire ks_w0 = start && (key_load || !ax_loaded) &&
                 ((phase == PHASE_IDLE) || (phase == PHASE_CRYPT));
  wire ks_w1 = (phase == PHASE_KEYEXP_A);
  wire ks_w2 = (phase == PHASE_KEYEXP_B);
  wire ks_we = ks_w0 | ks_w1 | ks_w2;
  wire [3:0] ks_wa = ks_w0 ? 4'd0 : (ks_w1 ? 4'd1 : rke);
  wire [127:0] ks_wd = ks_w0 ? key[255:128] : (ks_w1 ? k1_r : {we0, we1, we2, we3});

  reg ks_we_r;
  reg [3:0] ks_wa_r;
  reg [127:0] ks_wd_r;
  always @(posedge clk) begin
    ks_we_r <= ks_we;
    ks_wa_r <= ks_wa;
    ks_wd_r <= ks_wd;
  end

  bram_128x16 u_ksch (
      .clk(clk),
      .waddr(ks_wa_r),
      .wdata(ks_wd_r),
      .we(ks_we_r),
      .raddr(rd[b1]),
      .rdata(ksch_q)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phase <= PHASE_IDLE;
      rke <= 4'd0;
      ax_loaded <= 1'b0;
      k0_r <= 128'd0;
      k1_r <= 128'd0;
      st_prev <= 128'd0;
      st_prev2 <= 128'd0;
      state[0] <= 128'd0;
      state[1] <= 128'd0;
      state[2] <= 128'd0;
      sbox_c_d <= 128'd0;
      rd[0] <= 4'd0;
      rd[1] <= 4'd0;
      rd[2] <= 4'd0;
      blk_sel <= 2'd0;
      blk_sel_d <= 2'd0;
      b1_d <= 2'd2;
      out_r <= 128'd0;
      done_q <= 1'b0;
      crypt_rdy_q <= 1'b0;
    end else begin
      sbox_c_d <= sbox_c;
      if (ks_w0) begin
        k0_r <= key[255:128];
        k1_r <= key[127:0];
      end
      case (phase)
        PHASE_IDLE: begin
          if (start) begin
            if (key_load || !ax_loaded) begin
              st_prev <= key[127:0];
              st_prev2 <= key[255:128];
              rke <= 4'd2;
              phase <= PHASE_KEYEXP_A;
              crypt_rdy_q <= 1'b0;
            end else begin
              phase <= PHASE_CRYPT;
              crypt_rdy_q <= 1'b1;
            end
          end
        end
        PHASE_KEYEXP_A: begin
          phase <= PHASE_KEYEXP_B;
        end
        PHASE_KEYEXP_B: begin
          st_prev2 <= st_prev;
          st_prev  <= {we0, we1, we2, we3};
          if (rke == 4'd14) begin
            ax_loaded <= 1'b1;
            phase <= PHASE_CRYPT;
            crypt_rdy_q <= 1'b1;
          end else begin
            rke <= rke + 4'd1;
            phase <= PHASE_KEYEXP_A;
            crypt_rdy_q <= 1'b0;
          end
        end
        PHASE_CRYPT: begin
          if (start && (key_load || !ax_loaded)) begin
            rd[0] <= 4'd0;
            rd[1] <= 4'd0;
            rd[2] <= 4'd0;
            state[0] <= 128'd0;
            state[1] <= 128'd0;
            state[2] <= 128'd0;
            sbox_c_d <= 128'd0;
            blk_sel <= 2'd0;
            blk_sel_d <= 2'd0;
            b1_d <= 2'd2;
            st_prev <= key[127:0];
            st_prev2 <= key[255:128];
            rke <= 4'd2;
            phase <= PHASE_KEYEXP_A;
            crypt_rdy_q <= 1'b0;
          end else begin
            if (blk_valid && (rd[b2] == 4'd0)) begin
              state[b2] <= block_in ^ k0_r;
              rd[b2] <= 4'd1;
            end
            if (rd[b1_d] == 4'd14) begin
              state[b1_d] <= state_next;
              out_r <= state_next;
              if (blk_valid && (rd[b2] == 4'd1)) begin
                rd[b1_d] <= 4'd1;
                state[b1_d] <= block_in ^ k0_r;
              end else begin
                rd[b1_d] <= 4'd0;
              end
            end else if (rd[b1_d] != 4'd0) begin
              state[b1_d] <= state_next;
              rd[b1_d] <= rd[b1_d] + 4'd1;
            end
            done_q <= (rd[b1_d] == 4'd14);
            blk_sel_d <= blk_sel;
            b1_d <= b1;
            blk_sel <= (blk_sel == 2'd2) ? 2'd0 : blk_sel + 2'd1;
          end
        end
        default: phase <= PHASE_IDLE;
      endcase
    end
  end

  assign busy = (rd[0] != 4'd0) && (rd[1] != 4'd0) && (rd[2] != 4'd0);
  assign crypt_rdy = crypt_rdy_q;
  assign load_rdy = (phase == PHASE_CRYPT) && (rd[b2] == 4'd0) && !((key_load || !ax_loaded) && start);
  assign done = done_q;

endmodule
