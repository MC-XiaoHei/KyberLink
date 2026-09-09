module sbox16 (
    input  wire         clk,
    input  wire [127:0] x,
    output wire [127:0] y
);

  wire [7:0] y0, y1, y2, y3, y4, y5, y6, y7;
  wire [7:0] y8, y9, y10, y11, y12, y13, y14, y15;

  bp_aes_sbox u0 (
      .s_in(x[127:120]),
      .inv(1'b0),
      .s_out(y0)
  );
  bp_aes_sbox u1 (
      .s_in(x[119:112]),
      .inv(1'b0),
      .s_out(y1)
  );
  bp_aes_sbox u2 (
      .s_in(x[111:104]),
      .inv(1'b0),
      .s_out(y2)
  );
  bp_aes_sbox u3 (
      .s_in(x[103:96]),
      .inv(1'b0),
      .s_out(y3)
  );
  bp_aes_sbox u4 (
      .s_in(x[95:88]),
      .inv(1'b0),
      .s_out(y4)
  );
  bp_aes_sbox u5 (
      .s_in(x[87:80]),
      .inv(1'b0),
      .s_out(y5)
  );
  bp_aes_sbox u6 (
      .s_in(x[79:72]),
      .inv(1'b0),
      .s_out(y6)
  );
  bp_aes_sbox u7 (
      .s_in(x[71:64]),
      .inv(1'b0),
      .s_out(y7)
  );
  bp_aes_sbox u8 (
      .s_in(x[63:56]),
      .inv(1'b0),
      .s_out(y8)
  );
  bp_aes_sbox u9 (
      .s_in(x[55:48]),
      .inv(1'b0),
      .s_out(y9)
  );
  bp_aes_sbox u10 (
      .s_in(x[47:40]),
      .inv(1'b0),
      .s_out(y10)
  );
  bp_aes_sbox u11 (
      .s_in(x[39:32]),
      .inv(1'b0),
      .s_out(y11)
  );
  bp_aes_sbox u12 (
      .s_in(x[31:24]),
      .inv(1'b0),
      .s_out(y12)
  );
  bp_aes_sbox u13 (
      .s_in(x[23:16]),
      .inv(1'b0),
      .s_out(y13)
  );
  bp_aes_sbox u14 (
      .s_in(x[15:8]),
      .inv(1'b0),
      .s_out(y14)
  );
  bp_aes_sbox u15 (
      .s_in(x[7:0]),
      .inv(1'b0),
      .s_out(y15)
  );

  reg [127:0] y_r1;
  reg [127:0] y_r2;

  always @(posedge clk)
    y_r1 <= {
      y0, y1, y2, y3, y4, y5, y6, y7, y8, y9, y10, y11, y12, y13, y14, y15
    };

  always @(posedge clk) y_r2 <= y_r1;

  assign y = y_r2;

endmodule

