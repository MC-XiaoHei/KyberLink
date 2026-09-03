module mul_test (
    input  wire [127:0] a,
    input  wire [127:0] b,
    output wire [127:0] y
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

  wire [31:0] a0 = a[31:0], a1 = a[63:32], a2 = a[95:64], a3 = a[127:96];
  wire [31:0] b0 = b[31:0], b1 = b[63:32], b2 = b[95:64], b3 = b[127:96];
  wire [62:0] p0 = mul32f(a0, b0);
  wire [62:0] p1 = mul32f(a0, b1);
  wire [62:0] p2 = mul32f(a0, b2);
  wire [62:0] p3 = mul32f(a0, b3);
  wire [62:0] p4 = mul32f(a1, b0);
  wire [62:0] p5 = mul32f(a1, b1);
  wire [62:0] p6 = mul32f(a1, b2);
  wire [62:0] p7 = mul32f(a1, b3);
  wire [62:0] p8 = mul32f(a2, b0);
  wire [62:0] p9 = mul32f(a2, b1);
  wire [62:0] p10 = mul32f(a2, b2);
  wire [62:0] p11 = mul32f(a2, b3);
  wire [62:0] p12 = mul32f(a3, b0);
  wire [62:0] p13 = mul32f(a3, b1);
  wire [62:0] p14 = mul32f(a3, b2);
  wire [62:0] p15 = mul32f(a3, b3);

  wire [255:0] prod =
          ({193'd0, p0} << 0)   ^ ({193'd0, p1} << 32)  ^ ({193'd0, p2} << 64)  ^ ({193'd0, p3} << 96)
        ^ ({193'd0, p4} << 32)  ^ ({193'd0, p5} << 64)  ^ ({193'd0, p6} << 96)  ^ ({193'd0, p7} << 128)
        ^ ({193'd0, p8} << 64)  ^ ({193'd0, p9} << 96)  ^ ({193'd0, p10} << 128) ^ ({193'd0, p11} << 160)
        ^ ({193'd0, p12} << 96) ^ ({193'd0, p13} << 128) ^ ({193'd0, p14} << 160) ^ ({193'd0, p15} << 192);

  reg [255:0] red;
  integer ri;
  always @(*) begin
    red = prod;
    for (ri = 254; ri >= 128; ri = ri - 1) begin
      if (red[ri]) red[ri-128+:8] = red[ri-128+:8] ^ 8'h87;
    end
  end
  assign y = red[127:0];
endmodule
