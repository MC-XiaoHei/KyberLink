module aes256_core (
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
    output reg          done,
    output reg  [127:0] block_out
);

  localparam PHASE_IDLE     = 2'd0;
  localparam PHASE_KEYEXP_A = 2'd1;
  localparam PHASE_KEYEXP_B = 2'd2;
  localparam PHASE_CRYPT    = 2'd3;

  reg [  1:0] phase;
  reg [  3:0] rke;
  reg         ax_loaded;
  reg [127:0] st_prev;
  reg [127:0] st_prev2;
  reg [7:0] sb0_r, sb1_r, sb2_r, sb3_r;
  reg  [127:0] state      [0:3];
  reg  [127:0] sr_r       [0:3];
  reg  [127:0] rk_r       [0:3];
  reg  [  3:0] rd         [0:3];
  reg  [  1:0] blk_sel;
  reg  [  1:0] blk_sel_d;
  reg  [  1:0] blk_sel_dd;
  wire [  1:0] b1;

  function [7:0] gmul2(input [7:0] x);
    gmul2 = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
  endfunction

  function [7:0] gmul3(input [7:0] x);
    gmul3 = gmul2(x) ^ x;
  endfunction

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
  bp_aes_sbox u_sb_k0 (
      .s_in (wm1[31:24]),
      .inv  (1'b0),
      .s_out(sb0_c)
  );
  bp_aes_sbox u_sb_k1 (
      .s_in (wm1[23:16]),
      .inv  (1'b0),
      .s_out(sb1_c)
  );
  bp_aes_sbox u_sb_k2 (
      .s_in (wm1[15:8]),
      .inv  (1'b0),
      .s_out(sb2_c)
  );
  bp_aes_sbox u_sb_k3 (
      .s_in (wm1[7:0]),
      .inv  (1'b0),
      .s_out(sb3_c)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sb0_r <= 8'd0;
      sb1_r <= 8'd0;
      sb2_r <= 8'd0;
      sb3_r <= 8'd0;
    end else if (phase == PHASE_IDLE) begin
      sb0_r <= 8'd0;
      sb1_r <= 8'd0;
      sb2_r <= 8'd0;
      sb3_r <= 8'd0;
    end else begin
      sb0_r <= sb0_c;
      sb1_r <= sb1_c;
      sb2_r <= sb2_c;
      sb3_r <= sb3_c;
    end
  end

  wire [31:0] temp = rke[0]
        ? {sb0_r, sb1_r, sb2_r, sb3_r}
        : {sb1_r, sb2_r, sb3_r, sb0_r} ^ {rcon, 24'd0};
  wire [31:0] we0 = w8 ^ temp;
  wire [31:0] we1 = st_prev2[95:64] ^ we0;
  wire [31:0] we2 = st_prev2[63:32] ^ we1;
  wire [31:0] we3 = st_prev2[31:0] ^ we2;

  assign b1 = (blk_sel_dd == 2'd0) ? 2'd3 : blk_sel_dd - 2'd1;

  wire [1:0] b2 = (blk_sel == 2'd3) ? 2'd0 : blk_sel + 2'd1;
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
  wire [127:0] sbox_ca;
  sbox16 u_sb_a (
      .clk(clk),
      .x  (sr_in),
      .y  (sbox_ca)
  );

  wire [7:0] m0 = sr_r[b1][127:120];
  wire [7:0] m1 = sr_r[b1][119:112];
  wire [7:0] m2 = sr_r[b1][111:104];
  wire [7:0] m3 = sr_r[b1][103:96];
  wire [7:0] m4 = sr_r[b1][95:88];
  wire [7:0] m5 = sr_r[b1][87:80];
  wire [7:0] m6 = sr_r[b1][79:72];
  wire [7:0] m7 = sr_r[b1][71:64];
  wire [7:0] m8 = sr_r[b1][63:56];
  wire [7:0] m9 = sr_r[b1][55:48];
  wire [7:0] m10 = sr_r[b1][47:40];
  wire [7:0] m11 = sr_r[b1][39:32];
  wire [7:0] m12 = sr_r[b1][31:24];
  wire [7:0] m13 = sr_r[b1][23:16];
  wire [7:0] m14 = sr_r[b1][15:8];
  wire [7:0] m15 = sr_r[b1][7:0];

  wire [7:0] ca0 = gmul2(m0) ^ gmul3(m1) ^ m2 ^ m3;
  wire [7:0] ca1 = m0 ^ gmul2(m1) ^ gmul3(m2) ^ m3;
  wire [7:0] ca2 = m0 ^ m1 ^ gmul2(m2) ^ gmul3(m3);
  wire [7:0] ca3 = gmul3(m0) ^ m1 ^ m2 ^ gmul2(m3);
  wire [7:0] ca4 = gmul2(m4) ^ gmul3(m5) ^ m6 ^ m7;
  wire [7:0] ca5 = m4 ^ gmul2(m5) ^ gmul3(m6) ^ m7;
  wire [7:0] ca6 = m4 ^ m5 ^ gmul2(m6) ^ gmul3(m7);
  wire [7:0] ca7 = gmul3(m4) ^ m5 ^ m6 ^ gmul2(m7);
  wire [7:0] ca8 = gmul2(m8) ^ gmul3(m9) ^ m10 ^ m11;
  wire [7:0] ca9 = m8 ^ gmul2(m9) ^ gmul3(m10) ^ m11;
  wire [7:0] ca10 = m8 ^ m9 ^ gmul2(m10) ^ gmul3(m11);
  wire [7:0] ca11 = gmul3(m8) ^ m9 ^ m10 ^ gmul2(m11);
  wire [7:0] ca12 = gmul2(m12) ^ gmul3(m13) ^ m14 ^ m15;
  wire [7:0] ca13 = m12 ^ gmul2(m13) ^ gmul3(m14) ^ m15;
  wire [7:0] ca14 = m12 ^ m13 ^ gmul2(m14) ^ gmul3(m15);
  wire [7:0] ca15 = gmul3(m12) ^ m13 ^ m14 ^ gmul2(m15);
  wire [127:0] mc_a = {
    ca0, ca1, ca2, ca3, ca4, ca5, ca6, ca7, ca8, ca9, ca10, ca11, ca12, ca13, ca14, ca15
  };

  wire [127:0] mid = (rd[b1] == 4'd14) ? sr_r[b1] : mc_a;
  wire [127:0] state_na = mid ^ rk_r[b1];

  wire [1:0] b1_n = (b1 == 2'd3) ? 2'd0 : b1 + 2'd1;
  wire [3:0] ksch_ra = rd[b1_n] + 4'd1;
  wire [127:0] ksch_q;
  wire [127:0] rk = ksch_q;

  wire ks_wr0 = (phase == PHASE_IDLE || phase == PHASE_CRYPT) && start && (key_load || !ax_loaded);
  wire ks_wr1 = (phase == PHASE_KEYEXP_A) && (rke == 4'd2);
  wire ks_we = ks_wr0 | ks_wr1 | (phase == PHASE_KEYEXP_B);
  wire [3:0] ks_wa = ks_wr0 ? 4'd0 : ks_wr1 ? 4'd1 : rke;
  wire [127:0] ks_wd = ks_wr0 ? key[255:128] : ks_wr1 ? key[127:0] : {we0, we1, we2, we3};

  bram_128x256 u_ksch (
      .clk(clk),
      .waddr({4'd0, ks_wa}),
      .wdata(ks_wd),
      .we(ks_we),
      .raddr({4'd0, ksch_ra}),
      .rdata(ksch_q)
  );

  assign busy = (rd[0] != 4'd0) || (rd[1] != 4'd0) || (rd[2] != 4'd0) || (rd[3] != 4'd0);
  assign crypt_rdy = (phase == PHASE_CRYPT);
  assign load_rdy = (phase == PHASE_CRYPT) && (rd[b2] == 4'd0) && !((key_load || !ax_loaded) && start);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phase <= PHASE_IDLE;
      rke <= 4'd0;
      ax_loaded <= 1'b0;
      st_prev <= 128'd0;
      st_prev2 <= 128'd0;
      state[0] <= 128'd0;
      state[1] <= 128'd0;
      state[2] <= 128'd0;
      state[3] <= 128'd0;
      sr_r[0] <= 128'd0;
      sr_r[1] <= 128'd0;
      sr_r[2] <= 128'd0;
      sr_r[3] <= 128'd0;
      rk_r[0] <= 128'd0;
      rk_r[1] <= 128'd0;
      rk_r[2] <= 128'd0;
      rk_r[3] <= 128'd0;
      rd[0] <= 4'd0;
      rd[1] <= 4'd0;
      rd[2] <= 4'd0;
      rd[3] <= 4'd0;
      blk_sel <= 2'd0;
      blk_sel_d <= 2'd0;
      blk_sel_dd <= 2'd0;
      done <= 1'b0;
      block_out <= 128'd0;
    end else begin
      done <= 1'b0;
      case (phase)
        PHASE_IDLE: begin
          if (start) begin
            state[0] <= 128'd0;
            state[1] <= 128'd0;
            state[2] <= 128'd0;
            state[3] <= 128'd0;
            sr_r[0] <= 128'd0;
            sr_r[1] <= 128'd0;
            sr_r[2] <= 128'd0;
            sr_r[3] <= 128'd0;
            rk_r[0] <= 128'd0;
            rk_r[1] <= 128'd0;
            rk_r[2] <= 128'd0;
            rk_r[3] <= 128'd0;
            rd[0] <= 4'd0;
            rd[1] <= 4'd0;
            rd[2] <= 4'd0;
            rd[3] <= 4'd0;
            blk_sel <= 2'd0;
            blk_sel_d <= 2'd0;
            blk_sel_dd <= 2'd0;
            done <= 1'b0;
            if (key_load || !ax_loaded) begin
              st_prev <= key[127:0];
              st_prev2 <= key[255:128];
              rke <= 4'd2;
              phase <= PHASE_KEYEXP_A;
            end else begin
              phase <= PHASE_CRYPT;
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
          end else begin
            rke   <= rke + 4'd1;
            phase <= PHASE_KEYEXP_A;
          end
        end
        PHASE_CRYPT: begin
          if (blk_valid && (rd[b2] == 4'd0)) begin
            state[b2] <= block_in ^ key[255:128];
            rd[b2] <= 4'd1;
            rk_r[b2] <= key[127:0];
          end
          if (rd[blk_sel_dd] != 4'd0) sr_r[blk_sel_dd] <= sbox_ca;
          if (rd[b1] == 4'd14) begin
            rd[b1] <= 4'd0;
            done <= 1'b1;
            block_out <= state_na;
          end else if (rd[b1] != 4'd0) begin
            state[b1] <= state_na;
            rk_r[b1] <= rk;
            rd[b1] <= rd[b1] + 4'd1;
          end
          if (start) begin
            if (key_load || !ax_loaded) begin
              rd[0] <= 4'd0;
              rd[1] <= 4'd0;
              rd[2] <= 4'd0;
              rd[3] <= 4'd0;
              st_prev <= key[127:0];
              st_prev2 <= key[255:128];
              rke <= 4'd2;
              phase <= PHASE_KEYEXP_A;
            end
          end
          blk_sel_d <= blk_sel;
          blk_sel_dd <= blk_sel_d;
          blk_sel <= blk_sel + 2'd1;
        end
        default: phase <= PHASE_IDLE;
      endcase
    end
  end

endmodule
