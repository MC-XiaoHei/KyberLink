module pack_dsa (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire mode,
    input wire [4:0] d,
    input wire [5887:0] coeffs_in,
    input wire [5119:0] bytes_in,
    output reg busy,
    output reg done,
    output wire [5887:0] coeffs_out,
    output reg [5119:0] bytes_out
);
    reg [22:0] co_arr [0:255];

    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN = 1'b1;

    reg phase;
    reg [8:0] i;
    reg mode_r;
    reg [4:0] d_r;
    reg [7:0] pa;
    reg [7:0] pb;
    reg [7:0] pc;
    integer bfa_r;
    integer bfb_r;
    integer bfc_r;
    integer bj;
    integer pp;
    integer idm;

    wire [5119:0] pa32 = {5112'd0, pa};
    wire [5119:0] pb32 = {5112'd0, pb};
    wire [5119:0] pc32 = {5112'd0, pc};
    wire [9:0] bfa9 = bfa_r[9:0];
    wire [9:0] bfb9 = bfb_r[9:0];
    wire [9:0] bfc9 = bfc_r[9:0];
    wire [12:0] shfa = {bfa9, 3'd0};
    wire [12:0] shfb = {bfb9, 3'd0};
    wire [12:0] shfc = {bfc9, 3'd0};
    wire [12:0] sa = 13'd5112 - shfa;
    wire [12:0] sb = 13'd5112 - shfb;
    wire [12:0] sc = 13'd5112 - shfc;

    always @(*) begin
        pa = 8'd0;
        pb = 8'd0;
        pc = 8'd0;
        pp = 32'd0;
        idm = i * d_r;
        bfa_r = idm >> 3;
        bfb_r = (idm + {27'd0, d_r} - 1) >> 3;
        bfc_r = bfa_r + 1;
        for (bj = 0; bj < 24; bj = bj + 1) begin
            if (bj < d_r) begin
                pp = idm + bj;
                if ((pp >> 3) == bfa_r) begin
                    pa = pa | ({7'd0, coeffs_in[23 * i + bj]} << pp[2:0]);
                end else if ((pp >> 3) == bfb_r) begin
                    pb = pb | ({7'd0, coeffs_in[23 * i + bj]} << pp[2:0]);
                end else begin
                    pc = pc | ({7'd0, coeffs_in[23 * i + bj]} << pp[2:0]);
                end
            end
        end
    end

    function [22:0] gather(input [8:0] idx, input [4:0] dd, input [5119:0] bin);
        reg [4:0] k;
        reg [22:0] v;
        reg [12:0] n;
        begin
            v = 23'd0;
            for (k = 0; k < 24; k = k + 1) begin
                if (k < dd) begin
                    n = idx * dd + {8'd0, k};
                    v[k] = bin[13'd5112 - ({3'd0, n[12:3]} << 3) + {10'd0, n[2:0]}];
                end
            end
            gather = v;
        end
    endfunction

    wire [22:0] gv = gather(i, d_r, bytes_in);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            i <= 9'd0;
            mode_r <= 1'b0;
            d_r <= 5'd0;
            bytes_out <= 5120'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        mode_r <= mode;
                        d_r <= d;
                        i <= 9'd0;
                        bytes_out <= 5120'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    if (mode_r == 1'b0) begin
                        bytes_out <= bytes_out | (pa32 << sa) | (pb32 << sb) | (pc32 << sc);
                    end else begin
                        co_arr[i[7:0]] <= gv;
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
            assign coeffs_out[23 * gg +: 23] = co_arr[gg];
        end
    endgenerate

    wire [7:0] b_byte [0:639];
    genvar gb;
    generate
        for (gb = 0; gb < 640; gb = gb + 1) begin : g_by
            assign b_byte[gb] = bytes_out[5119 - 8 * gb -: 8];
        end
    endgenerate
endmodule
