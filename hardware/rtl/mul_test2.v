module mul_test2 (
    input wire clk,
    input wire [127:0] a,
    input wire [127:0] b,
    output reg [127:0] y
);
  function [14:0] mul8f(input [7:0] a8, input [7:0] b8);
    integer bi, bj;
    reg [14:0] acc;
    begin
      acc = 15'd0;
      for (bi = 0; bi < 8; bi = bi + 1)
      for (bj = 0; bj < 8; bj = bj + 1) acc[bi+bj] = acc[bi+bj] ^ (a8[bj] & b8[bi]);
      mul8f = acc;
    end
  endfunction

  function [30:0] mul16f(input [15:0] a16, input [15:0] b16);
    reg [14:0] m0, m1, m2;
    begin
      m0 = mul8f(a16[7:0], b16[7:0]);
      m1 = mul8f(a16[15:8], b16[15:8]);
      m2 = mul8f(a16[7:0] ^ a16[15:8], b16[7:0] ^ b16[15:8]);
      mul16f = {16'd0, m0} ^ {8'd0, m0 ^ m1 ^ m2, 8'b0} ^ {m1, 16'b0};
    end
  endfunction

  function [62:0] mul32f(input [31:0] a32, input [31:0] b32);
    reg [30:0] m0, m1, m2;
    begin
      m0 = mul16f(a32[15:0], b32[15:0]);
      m1 = mul16f(a32[31:16], b32[31:16]);
      m2 = mul16f(a32[15:0] ^ a32[31:16], b32[15:0] ^ b32[31:16]);
      mul32f = {32'd0, m0} ^ {16'd0, m0 ^ m1 ^ m2, 16'b0} ^ {m1, 32'b0};
    end
  endfunction

  reg [127:0] a_reg, b_reg;
  reg [255:0] prod;
  reg [1:0] cnt;
  reg [3:0] go;

  wire [31:0] a0 = a_reg[31:0], a1 = a_reg[63:32], a2 = a_reg[95:64], a3 = a_reg[127:96];
  wire [31:0] b0 = b_reg[31:0], b1 = b_reg[63:32], b2 = b_reg[95:64], b3 = b_reg[127:96];
  wire [31:0] ai = (cnt == 2'd0) ? a0 : (cnt == 2'd1) ? a1 : (cnt == 2'd2) ? a2 : a3;
  wire [62:0] mul_0 = mul32f(ai, b0);
  wire [62:0] mul_1 = mul32f(ai, b1);
  wire [62:0] mul_2 = mul32f(ai, b2);
  wire [62:0] mul_3 = mul32f(ai, b3);
  wire [3:0] ij_0 = {2'd0, cnt};
  wire [3:0] ij_1 = {2'd0, cnt} + 4'd1;
  wire [3:0] ij_2 = {2'd0, cnt} + 4'd2;
  wire [3:0] ij_3 = {2'd0, cnt} + 4'd3;
  wire [255:0] shifted = ({193'd0, mul_0} << ({4'd0, ij_0} << 5)) ^
                           ({193'd0, mul_1} << ({4'd0, ij_1} << 5)) ^
                           ({193'd0, mul_2} << ({4'd0, ij_2} << 5)) ^
                           ({193'd0, mul_3} << ({4'd0, ij_3} << 5));

  reg [255:0] red;
  integer ri;
  always @(*) begin
    red = prod;
    for (ri = 254; ri >= 128; ri = ri - 1) begin
      if (red[ri]) red[ri-128+:8] = red[ri-128+:8] ^ 8'h87;
    end
  end

  always @(posedge clk) begin
    if (go == 4'd0) begin
      a_reg <= a;
      b_reg <= b;
      prod <= 256'd0;
      cnt <= 2'd0;
      go <= 4'd1;
    end else if (go <= 4'd4) begin
      prod <= prod ^ shifted;
      cnt  <= cnt + 2'd1;
      go   <= go + 4'd1;
    end else begin
      y  <= red[127:0];
      go <= 4'd0;
    end
  end
endmodule
