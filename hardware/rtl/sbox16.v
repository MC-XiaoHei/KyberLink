module sbox16 (
    input  wire         clk,
    input  wire [127:0] x,
    output wire [127:0] y
);

  wire [7:0] y0, y1, y2, y3, y4, y5, y6, y7;
  wire [7:0] y8, y9, y10, y11, y12, y13, y14, y15;

  sbox8 u0 (
      .x(x[127:120]),
      .y(y0)
  );
  sbox8 u1 (
      .x(x[119:112]),
      .y(y1)
  );
  sbox8 u2 (
      .x(x[111:104]),
      .y(y2)
  );
  sbox8 u3 (
      .x(x[103:96]),
      .y(y3)
  );
  sbox8 u4 (
      .x(x[95:88]),
      .y(y4)
  );
  sbox8 u5 (
      .x(x[87:80]),
      .y(y5)
  );
  sbox8 u6 (
      .x(x[79:72]),
      .y(y6)
  );
  sbox8 u7 (
      .x(x[71:64]),
      .y(y7)
  );
  sbox8 u8 (
      .x(x[63:56]),
      .y(y8)
  );
  sbox8_dist u9 (
      .x(x[55:48]),
      .y(y9)
  );
  sbox8_dist u10 (
      .x(x[47:40]),
      .y(y10)
  );
  sbox8_dist u11 (
      .x(x[39:32]),
      .y(y11)
  );
  sbox8_dist u12 (
      .x(x[31:24]),
      .y(y12)
  );
  sbox8_dist u13 (
      .x(x[23:16]),
      .y(y13)
  );
  sbox8_dist u14 (
      .x(x[15:8]),
      .y(y14)
  );
  sbox8_dist u15 (
      .x(x[7:0]),
      .y(y15)
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

