module ghash (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [127:0] h,
    input  wire [127:0] data_in,
    input  wire data_valid,
    input  wire [7:0] nblocks,
    output reg busy,
    output reg done,
    output wire [127:0] tag
);

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;

    reg [1:0] phase;
    reg [127:0] yacc;
    reg [7:0] blk;

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

    function [14:0] mul8f(input [7:0] a, input [7:0] b);
        integer bi, bj;
        reg [14:0] acc;
        begin
            acc = 15'd0;
            for (bi = 0; bi < 8; bi = bi + 1)
                for (bj = 0; bj < 8; bj = bj + 1)
                    acc[bi+bj] = acc[bi+bj] ^ (a[bj] & b[bi]);
            mul8f = acc;
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

    function [126:0] mul64f(input [63:0] a, input [63:0] b);
        reg [62:0] m0, m1, m2;
        reg [126:0] pk;
        begin
            m0 = mul32f(a[31:0], b[31:0]);
            m1 = mul32f(a[63:32], b[63:32]);
            m2 = mul32f(a[31:0] ^ a[63:32], b[31:0] ^ b[63:32]);
            pk = {64'd0, m0} ^ {32'd0, m0 ^ m1 ^ m2, 32'b0} ^ {m1, 64'b0};
            mul64f = pk;
        end
    endfunction

    function [254:0] mul128f(input [127:0] a, input [127:0] b);
        reg [126:0] m0, m1, m2;
        reg [254:0] pk;
        begin
            m0 = mul64f(a[63:0], b[63:0]);
            m1 = mul64f(a[127:64], b[127:64]);
            m2 = mul64f(a[63:0] ^ a[127:64], b[63:0] ^ b[127:64]);
            pk = {128'd0, m0} ^ {64'd0, m0 ^ m1 ^ m2, 64'b0} ^ {m1, 128'b0};
            mul128f = pk;
        end
    endfunction

    reg [254:0] red;
    integer ri;
    always @(*) begin
        red = mul128f(yacc ^ d_rev, h_rev);
        for (ri = 254; ri >= 128; ri = ri - 1) begin
            if (red[ri]) red[ri-128 +: 8] = red[ri-128 +: 8] ^ 8'h87;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            yacc <= 128'd0;
            blk <= 8'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        yacc <= 128'd0;
                        blk <= 8'd0;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    if (data_valid) begin
                        yacc <= red[127:0];
                        if (blk + 8'd1 >= nblocks) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end else begin
                            blk <= blk + 8'd1;
                        end
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
