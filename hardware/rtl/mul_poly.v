module mul_poly #(
    parameter W = 8
)(
    input  wire [W-1:0]     a,
    input  wire [W-1:0]     b,
    output wire [2*W-2:0]   p
);
    generate
        if (W == 8) begin : g_base
            integer bi, bj;
            reg [14:0] acc;
            always @(*) begin
                acc = 15'd0;
                for (bi = 0; bi < 8; bi = bi + 1)
                    for (bj = 0; bj < 8; bj = bj + 1)
                        acc[bi+bj] = acc[bi+bj] ^ (a[bj] & b[bi]);
            end
            assign p = acc;
        end else begin : g_kar
            localparam N = W / 2;
            wire [N-1:0] a0 = a[N-1:0];
            wire [N-1:0] a1 = a[W-1:N];
            wire [N-1:0] b0 = b[N-1:0];
            wire [N-1:0] b1 = b[W-1:N];
            wire [2*N-2:0] m0, m1, m2;
            mul_poly #(.W(N)) u_m0 (.a(a0), .b(b0), .p(m0));
            mul_poly #(.W(N)) u_m1 (.a(a1), .b(b1), .p(m1));
            mul_poly #(.W(N)) u_m2 (.a(a0 ^ a1), .b(b0 ^ b1), .p(m2));
            wire [2*N-2:0] mid = m0 ^ m1 ^ m2;
            wire [4*N-2:0] pk;
            assign pk = {{(2*N){1'b0}}, m0}
                      ^ {{(N){1'b0}}, mid, {(N){1'b0}}}
                      ^ {{(2*N){1'b0}}, m1};
            assign p = pk;
        end
    endgenerate
endmodule
