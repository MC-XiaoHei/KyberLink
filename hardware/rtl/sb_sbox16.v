module sb_sbox16 (
    input  wire        clk,
    input  wire [127:0] x,
    output wire [127:0] y
);
    wire [7:0] y0, y1, y2, y3, y4, y5, y6, y7;
    wire [7:0] y8, y9, y10, y11, y12, y13, y14, y15;
    sbox_combo_cf_lut #(.PIPE(1)) u0  (.clk(clk), .x(x[127:120]), .y(y0));
    sbox_combo_cf_lut #(.PIPE(1)) u1  (.clk(clk), .x(x[119:112]), .y(y1));
    sbox_combo_cf_lut #(.PIPE(1)) u2  (.clk(clk), .x(x[111:104]), .y(y2));
    sbox_combo_cf_lut #(.PIPE(1)) u3  (.clk(clk), .x(x[103:96]),  .y(y3));
    sbox_combo_cf_lut #(.PIPE(1)) u4  (.clk(clk), .x(x[95:88]),   .y(y4));
    sbox_combo_cf_lut #(.PIPE(1)) u5  (.clk(clk), .x(x[87:80]),   .y(y5));
    sbox_combo_cf_lut #(.PIPE(1)) u6  (.clk(clk), .x(x[79:72]),   .y(y6));
    sbox_combo_cf_lut #(.PIPE(1)) u7  (.clk(clk), .x(x[71:64]),   .y(y7));
    sbox_combo_cf_lut #(.PIPE(1)) u8  (.clk(clk), .x(x[63:56]),   .y(y8));
    sbox_combo_cf_lut #(.PIPE(1)) u9  (.clk(clk), .x(x[55:48]),   .y(y9));
    sbox_combo_cf_lut #(.PIPE(1)) u10 (.clk(clk), .x(x[47:40]),   .y(y10));
    sbox_combo_cf_lut #(.PIPE(1)) u11 (.clk(clk), .x(x[39:32]),   .y(y11));
    sbox_combo_cf_lut #(.PIPE(1)) u12 (.clk(clk), .x(x[31:24]),   .y(y12));
    sbox_combo_cf_lut #(.PIPE(1)) u13 (.clk(clk), .x(x[23:16]),   .y(y13));
    sbox_combo_cf_lut #(.PIPE(1)) u14 (.clk(clk), .x(x[15:8]),    .y(y14));
    sbox_combo_cf_lut #(.PIPE(1)) u15 (.clk(clk), .x(x[7:0]),     .y(y15));
    reg [127:0] y_r;
    always @(posedge clk) begin
        y_r <= {y0, y1, y2, y3, y4, y5, y6, y7,
                y8, y9, y10, y11, y12, y13, y14, y15};
    end
    assign y = y_r;
endmodule
