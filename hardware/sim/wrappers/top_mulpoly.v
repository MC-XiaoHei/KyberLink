module top_mulpoly (
    input  wire [127:0] a,
    input  wire [127:0] b,
    output wire [254:0] p
);
    mul_poly #(.W(128)) u_mp (.a(a), .b(b), .p(p));
endmodule
