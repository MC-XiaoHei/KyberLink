module sbox_combo (
    input  wire [7:0] x,
    output wire [7:0] y
);

    wire [3:0] a =
        {x[5]^x[7], x[2]^x[3]^x[5]^x[7], x[1]^x[4]^x[6]^x[7], x[4]^x[5]^x[6]};
    wire [3:0] b =
        {x[3]^x[4], x[2]^x[3]^x[4]^x[5]^x[6]^x[7], x[2], x[0]^x[5]^x[7]};

    wire [3:0] a2 = gf16_sq(a);
    wire [3:0] b2 = gf16_sq(b);
    wire [3:0] ab = gf16_mul(a, b);
    wire [3:0] n  = gf16_mul(a2, 4'h8) ^ ab ^ b2;
    wire [3:0] ti = gf16_inv(n);

    wire [3:0] va = gf16_mul(a, ti);
    wire [3:0] vb = gf16_mul(a ^ b, ti);
    wire [7:0] ic = {va, vb};

    wire [7:0] ly;
    assign ly[0] = ic[0] ^ ic[2] ^ ic[6];
    assign ly[1] = ic[0] ^ ic[1] ^ ic[2] ^ ic[3] ^ ic[4] ^ ic[5];
    assign ly[2] = ic[0] ^ ic[3] ^ ic[5] ^ ic[6];
    assign ly[3] = ic[0] ^ ic[2] ^ ic[5];
    assign ly[4] = ic[0] ^ ic[1] ^ ic[3] ^ ic[4] ^ ic[5];
    assign ly[5] = ic[1] ^ ic[2] ^ ic[3] ^ ic[5] ^ ic[6] ^ ic[7];
    assign ly[6] = ic[4] ^ ic[6] ^ ic[7];
    assign ly[7] = ic[1] ^ ic[2];

    assign y = ly ^ 8'h63;

    function [3:0] gf16_sq(input [3:0] v);
        begin
            gf16_sq = {v[3], v[1]^v[3], v[2], v[0]^v[2]};
        end
    endfunction

    function [3:0] gf16_mul(input [3:0] p, input [3:0] q);
        begin
            gf16_mul[0] = (p[0]&q[0]) ^ (p[1]&q[3]) ^ (p[2]&q[2]) ^ (p[3]&q[1]);
            gf16_mul[1] = (p[0]&q[1]) ^ (p[1]&q[0]) ^ (p[1]&q[3]) ^ (p[2]&q[2]) ^ (p[3]&q[1]) ^ (p[2]&q[3]) ^ (p[3]&q[2]);
            gf16_mul[2] = (p[0]&q[2]) ^ (p[1]&q[1]) ^ (p[2]&q[0]) ^ (p[2]&q[3]) ^ (p[3]&q[2]) ^ (p[3]&q[3]);
            gf16_mul[3] = (p[0]&q[3]) ^ (p[1]&q[2]) ^ (p[2]&q[1]) ^ (p[3]&q[0]) ^ (p[3]&q[3]);
        end
    endfunction

    function [3:0] gf16_inv(input [3:0] p);
        begin
            case (p)
                4'h0: gf16_inv = 4'h0;
                4'h1: gf16_inv = 4'h1;
                4'h2: gf16_inv = 4'h9;
                4'h3: gf16_inv = 4'he;
                4'h4: gf16_inv = 4'hd;
                4'h5: gf16_inv = 4'hb;
                4'h6: gf16_inv = 4'h7;
                4'h7: gf16_inv = 4'h6;
                4'h8: gf16_inv = 4'hf;
                4'h9: gf16_inv = 4'h2;
                4'ha: gf16_inv = 4'hc;
                4'hb: gf16_inv = 4'h5;
                4'hc: gf16_inv = 4'ha;
                4'hd: gf16_inv = 4'h4;
                4'he: gf16_inv = 4'h3;
                4'hf: gf16_inv = 4'h8;
            endcase
        end
    endfunction

endmodule
