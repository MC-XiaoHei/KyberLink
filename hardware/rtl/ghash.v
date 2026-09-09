module ghash (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [127:0] h,
    input wire [127:0] data_in,
    input wire data_valid,
    input wire [7:0] nblocks,
    output reg busy,
    output reg done,
    output reg ready,
    output reg block_done,
    output reg accept,
    output wire [127:0] tag
);

  localparam PHASE_IDLE = 3'd0;
  localparam PHASE_RUN  = 3'd1;
  localparam PHASE_PRE  = 3'd2;
  localparam PHASE_MUL  = 3'd3;
  localparam PHASE_RED  = 3'd4;

  reg [  2:0] phase;
  reg [127:0] yacc;
  reg [  7:0] blk;
  reg [  2:0] cnt;
  reg [255:0] prod;
  reg [127:0] a_reg;
  reg [127:0] b_reg;

  genvar gi;
  wire [127:0] h_rev;
  wire [127:0] d_rev;
  generate
    for (gi = 0; gi < 128; gi = gi + 1) begin : grev_h
      assign h_rev[gi] = h[127-gi];
    end
    for (gi = 0; gi < 128; gi = gi + 1) begin : grev_d
      assign d_rev[gi] = data_in[127-gi];
    end
    for (gi = 0; gi < 128; gi = gi + 1) begin : grev_t
      assign tag[gi] = yacc[127-gi];
    end
  endgenerate

  function [7:0] mul4f(input [3:0] a, input [3:0] b);
    integer bi, bj;
    reg [7:0] acc;
    begin
      acc = 8'd0;
      for (bi = 0; bi < 4; bi = bi + 1)
      for (bj = 0; bj < 4; bj = bj + 1) acc[bi+bj] = acc[bi+bj] ^ (a[bj] & b[bi]);
      mul4f = acc;
    end
  endfunction

  function [14:0] mul8f(input [7:0] a, input [7:0] b);
    reg [7:0] m0, m1, m2;
    begin
      m0 = mul4f(a[3:0], b[3:0]);
      m1 = mul4f(a[7:4], b[7:4]);
      m2 = mul4f(a[3:0] ^ a[7:4], b[3:0] ^ b[7:4]);
      mul8f = {8'd0, m0} ^ {4'd0, m0 ^ m1 ^ m2, 4'b0} ^ {m1, 8'b0};
    end
  endfunction

  function [30:0] mul16f(input [15:0] a, input [15:0] b);
    reg [14:0] m0, m1, m2;
    reg [30:0] pk;
    begin
      m0 = mul8f(a[7:0], b[7:0]);
      m1 = mul8f(a[15:8], b[15:8]);
      m2 = mul8f(a[7:0] ^ a[15:8], b[7:0] ^ b[15:8]);
      pk = {16'd0, m0} ^ {8'd0, m0 ^ m1 ^ m2, 8'b0} ^ {m1, 16'b0};
      mul16f = pk;
    end
  endfunction

  function [62:0] mul32f(input [31:0] a, input [31:0] b);
    reg [30:0] m0, m1, m2;
    reg [62:0] pk;
    begin
      m0 = mul16f(a[15:0], b[15:0]);
      m1 = mul16f(a[31:16], b[31:16]);
      m2 = mul16f(a[15:0] ^ a[31:16], b[15:0] ^ b[31:16]);
      pk = {32'd0, m0} ^ {16'd0, m0 ^ m1 ^ m2, 16'b0} ^ {m1, 32'b0};
      mul32f = pk;
    end
  endfunction

  wire [31:0] a_h0 = a_reg[31:0];
  wire [31:0] a_h1 = a_reg[63:32];
  wire [31:0] a_h2 = a_reg[95:64];
  wire [31:0] a_h3 = a_reg[127:96];
  wire [31:0] b_h0 = b_reg[31:0];
  wire [31:0] b_h1 = b_reg[63:32];
  wire [31:0] b_h2 = b_reg[95:64];
  wire [31:0] b_h3 = b_reg[127:96];

  wire [ 2:0] cnt1 = cnt + 3'd1;
  wire [ 1:0] nx_i = cnt1[2:1];
  wire [ 1:0] nx_0 = {cnt1[0], 1'b0};
  wire [ 1:0] nx_1 = {cnt1[0], 1'b1};
  wire [31:0] nx_w0 = (nx_i == 2'd0) ? a_h0 : (nx_i == 2'd1) ? a_h1 : (nx_i == 2'd2) ? a_h2 : a_h3;
  wire [31:0] nx_w1 = (nx_0 == 2'd0) ? b_h0 : (nx_0 == 2'd1) ? b_h1 : (nx_0 == 2'd2) ? b_h2 : b_h3;
  wire [31:0] nx_w2 = (nx_1 == 2'd0) ? b_h0 : (nx_1 == 2'd1) ? b_h1 : (nx_1 == 2'd2) ? b_h2 : b_h3;
  wire [ 4:0] nx_s0 = {2'd0, nx_i} + {2'd0, nx_0};
  wire [ 4:0] nx_s1 = {2'd0, nx_i} + {2'd0, nx_1};

  reg [31:0] aw_r, bw0_r, bw1_r;
  reg [4:0] sh0_r, sh1_r;
  wire [62:0] mul_a = mul32f(aw_r, bw0_r);
  wire [62:0] mul_b = mul32f(aw_r, bw1_r);
  wire [255:0] shifted = ({193'd0, mul_a} << ({2'b00, sh0_r, 5'd0})) ^
                           ({193'd0, mul_b} << ({2'b00, sh1_r, 5'd0}));

  reg [255:0] red;
  reg [  5:0] rcorr;
  integer ri;
  always @(*) begin
    red = prod;
    for (ri = 254; ri >= 134; ri = ri - 1) begin
      if (prod[ri]) red[ri-128+:8] = red[ri-128+:8] ^ 8'h87;
    end
    rcorr[0] = prod[249] ^ prod[254];
    rcorr[1] = prod[250];
    rcorr[2] = prod[251];
    rcorr[3] = prod[252];
    rcorr[4] = prod[253];
    rcorr[5] = prod[254];
    for (ri = 133; ri >= 128; ri = ri - 1) begin
      if (prod[ri] ^ rcorr[ri-128]) red[ri-128+:8] = red[ri-128+:8] ^ 8'h87;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phase <= PHASE_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      ready <= 1'b1;
      block_done <= 1'b0;
      accept <= 1'b0;
      yacc <= 128'd0;
      blk <= 8'd0;
      cnt <= 3'd0;
      prod <= 256'd0;
      a_reg <= 128'd0;
      b_reg <= 128'd0;
    end else begin
      done <= 1'b0;
      accept <= 1'b0;
      block_done <= 1'b0;
      case (phase)
        PHASE_IDLE: begin
          ready <= 1'b1;
          if (start) begin
            busy  <= 1'b1;
            yacc  <= 128'd0;
            blk   <= 8'd0;
            phase <= PHASE_RUN;
          end
        end
        PHASE_RUN: begin
          if (data_valid) begin
            ready <= 1'b0;
            accept <= 1'b1;
            a_reg <= yacc ^ d_rev;
            b_reg <= h_rev;
            prod <= 256'd0;
            cnt <= 3'd0;
            phase <= PHASE_PRE;
          end
        end
        PHASE_PRE: begin
          aw_r  <= a_h0;
          bw0_r <= b_h0;
          bw1_r <= b_h1;
          sh0_r <= 5'd0;
          sh1_r <= 5'd1;
          phase <= PHASE_MUL;
        end

        PHASE_MUL: begin
          prod  <= prod ^ shifted;
          aw_r  <= nx_w0;
          bw0_r <= nx_w1;
          bw1_r <= nx_w2;
          sh0_r <= nx_s0;
          sh1_r <= nx_s1;
          if (cnt == 3'd7) begin
            phase <= PHASE_RED;
          end else begin
            cnt <= cnt + 3'd1;
          end
        end
        PHASE_RED: begin
          block_done <= 1'b1;
          if (blk + 8'd1 >= nblocks) begin
            yacc  <= red[127:0];
            busy  <= 1'b0;
            done  <= 1'b1;
            phase <= PHASE_IDLE;
          end else begin
            yacc  <= red[127:0];
            ready <= 1'b1;
            blk   <= blk + 8'd1;
            phase <= PHASE_RUN;
          end
        end
        default: phase <= PHASE_IDLE;
      endcase
    end
  end
endmodule
