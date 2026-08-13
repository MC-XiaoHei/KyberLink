module pack (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire mode,
    input wire [3:0] d,
    input wire [3071:0] coeffs_in,
    input wire [3071:0] bytes_in,
    output reg busy,
    output reg done,
    output wire [3071:0] coeffs_out,
    output reg [3071:0] bytes_out
);
    reg [11:0] co_arr [0:255];

    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN = 1'b1;

    reg phase;
    reg [8:0] i;
    reg mode_r;
    reg [3:0] d_r;
    reg [7:0] pa;
    reg [7:0] pb;
    integer bfa_r;
    integer bfb_r;
    integer bj;
    integer pp;

    wire [3071:0] pa32 = {3064'd0, pa};
    wire [3071:0] pb32 = {3064'd0, pb};
    wire [8:0] bfa9 = bfa_r[8:0];
    wire [8:0] bfb9 = bfb_r[8:0];
    wire [11:0] shfa = {bfa9, 3'd0};
    wire [11:0] shfb = {bfb9, 3'd0};
    wire [11:0] sa = 12'd3064 - shfa;
    wire [11:0] sb = 12'd3064 - shfb;

    always @(*) begin
        pa = 8'd0;
        pb = 8'd0;
        pp = 32'd0;
        bfa_r = (i * d_r) >> 3;
        bfb_r = (i * d_r + {28'd0, d_r} - 1) >> 3;
        for (bj = 0; bj < 12; bj = bj + 1) begin
            if (bj < d_r) begin
                pp = i * d_r + bj;
                if ((pp >> 3) == bfa_r) begin
                    pa = pa | ({7'd0, coeffs_in[12 * i + bj]} << pp[2:0]);
                end else begin
                    pb = pb | ({7'd0, coeffs_in[12 * i + bj]} << pp[2:0]);
                end
            end
        end
    end

    function [11:0] gather(input [8:0] idx, input [3:0] dd, input [3071:0] bin);
        reg [3:0] k;
        reg [11:0] v;
        reg [12:0] n;
        begin
            v = 12'd0;
            for (k = 0; k < 12; k = k + 1) begin
                if (k < dd) begin
                    n = idx * dd + {9'd0, k};
                    v[k] = bin[12'd3064 - ({3'd0, n[11:3]} << 3) + {9'd0, n[2:0]}];
                end
            end
            gather = v;
        end
    endfunction

    wire [11:0] gv = gather(i, d_r, bytes_in);
    wire [11:0] gv_adj = ((d_r == 4'd12) && (gv >= 12'd3329)) ? (gv + 12'd767) : gv;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            i <= 9'd0;
            mode_r <= 1'b0;
            d_r <= 4'd0;
            bytes_out <= 3072'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        mode_r <= mode;
                        d_r <= d;
                        i <= 9'd0;
                        bytes_out <= 3072'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    if (mode_r == 1'b0) begin
                        bytes_out <= bytes_out | (pa32 << sa) | (pb32 << sb);
                    end else begin
                        co_arr[i[7:0]] <= gv_adj;
                    end
                    if (i == 9'd255) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        i <= i + 9'd1;
                    end
                end
            endcase
        end
    end

    genvar gg;
    generate
        for (gg = 0; gg < 256; gg = gg + 1) begin : g_co
            assign coeffs_out[12 * gg +: 12] = co_arr[gg];
        end
    endgenerate

    wire [7:0] b_byte [0:383];
    genvar gb;
    generate
        for (gb = 0; gb < 384; gb = gb + 1) begin : g_by
            assign b_byte[gb] = bytes_out[3071 - 8 * gb -: 8];
        end
    endgenerate
endmodule
