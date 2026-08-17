module keccak_f1600_round (
    input  wire [1599:0] state_in,
    input  wire [4:0]    round,
    output wire [1599:0] state_out
);
    function automatic [5:0] rotv;
        input [2:0] xx;
        input [2:0] yy;
        case (xx)
            3'd0: case (yy)
                3'd0: rotv = 6'd0;  3'd1: rotv = 6'd36; 3'd2: rotv = 6'd3;
                3'd3: rotv = 6'd41; 3'd4: rotv = 6'd18;
                default: rotv = 6'd0;
            endcase
            3'd1: case (yy)
                3'd0: rotv = 6'd1;  3'd1: rotv = 6'd44; 3'd2: rotv = 6'd10;
                3'd3: rotv = 6'd45; 3'd4: rotv = 6'd2;
                default: rotv = 6'd0;
            endcase
            3'd2: case (yy)
                3'd0: rotv = 6'd62; 3'd1: rotv = 6'd6;  3'd2: rotv = 6'd43;
                3'd3: rotv = 6'd15; 3'd4: rotv = 6'd61;
                default: rotv = 6'd0;
            endcase
            3'd3: case (yy)
                3'd0: rotv = 6'd28; 3'd1: rotv = 6'd55; 3'd2: rotv = 6'd25;
                3'd3: rotv = 6'd21; 3'd4: rotv = 6'd56;
                default: rotv = 6'd0;
            endcase
            default: case (yy)
                3'd0: rotv = 6'd27; 3'd1: rotv = 6'd20; 3'd2: rotv = 6'd39;
                3'd3: rotv = 6'd8;  3'd4: rotv = 6'd14;
                default: rotv = 6'd0;
            endcase
        endcase
    endfunction

    reg [63:0] A [0:4][0:4];
    reg [63:0] C [0:4];
    reg [63:0] D [0:4];
    reg [63:0] B [0:4][0:4];
    reg [63:0] O [0:4][0:4];
    reg [1599:0] so;
    reg [63:0] rc;
    reg [5:0]  rv;
    integer i, x, y;

    always @(*) begin
        case (round)
            5'd0:  rc = 64'h0000000000000001;
            5'd1:  rc = 64'h0000000000008082;
            5'd2:  rc = 64'h800000000000808A;
            5'd3:  rc = 64'h8000000080008000;
            5'd4:  rc = 64'h000000000000808B;
            5'd5:  rc = 64'h0000000080000001;
            5'd6:  rc = 64'h8000000080008081;
            5'd7:  rc = 64'h8000000000008009;
            5'd8:  rc = 64'h000000000000008A;
            5'd9:  rc = 64'h0000000000000088;
            5'd10: rc = 64'h0000000080008009;
            5'd11: rc = 64'h000000008000000A;
            5'd12: rc = 64'h000000008000808B;
            5'd13: rc = 64'h800000000000008B;
            5'd14: rc = 64'h8000000000008089;
            5'd15: rc = 64'h8000000000008003;
            5'd16: rc = 64'h8000000000008002;
            5'd17: rc = 64'h8000000000000080;
            5'd18: rc = 64'h000000000000800A;
            5'd19: rc = 64'h800000008000000A;
            5'd20: rc = 64'h8000000080008081;
            5'd21: rc = 64'h8000000000008080;
            5'd22: rc = 64'h0000000080000001;
            5'd23: rc = 64'h8000000080008008;
            default: rc = 64'h0;
        endcase
        for (i = 0; i < 25; i = i + 1)
            A[i % 5][i / 5] = state_in[64*i +: 64];
        for (x = 0; x < 5; x = x + 1)
            C[x] = A[x][0] ^ A[x][1] ^ A[x][2] ^ A[x][3] ^ A[x][4];
        for (x = 0; x < 5; x = x + 1)
            D[x] = C[(x + 4) % 5] ^ {C[(x + 1) % 5][62:0], C[(x + 1) % 5][63]};
        for (x = 0; x < 5; x = x + 1) begin
            for (y = 0; y < 5; y = y + 1) begin
                rv = rotv(x[2:0], y[2:0]);
                B[y][(2*x + 3*y) % 5] = ((A[x][y] ^ D[x]) << rv) |
                                        ((A[x][y] ^ D[x]) >> (7'd64 - {1'b0, rv}));
            end
        end
        for (x = 0; x < 5; x = x + 1) begin
            for (y = 0; y < 5; y = y + 1)
                O[x][y] = B[x][y] ^ ((~B[(x + 1) % 5][y]) & B[(x + 2) % 5][y]);
        end
        O[0][0] = O[0][0] ^ rc;
        for (i = 0; i < 25; i = i + 1)
            so[64*i +: 64] = O[i % 5][i / 5];
    end

    assign state_out = so;
endmodule
