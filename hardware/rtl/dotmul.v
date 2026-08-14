module dotmul (
    input wire clk,
    input wire rst_n,
    input wire start,
    input wire [9215:0] a_in,
    input wire [9215:0] b_in,
    output reg busy,
    output reg done,
    output wire [3071:0] c_out
);
    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN = 1'b1;
    localparam Q = 13'd3329;

    reg phase;
    reg [8:0] p;
    reg [11:0] a_arr [0:2][0:255];
    reg [11:0] b_arr [0:2][0:255];
    reg [11:0] c_arr [0:767];
    reg [11:0] acc0;
    reg [11:0] acc1;

    integer jj;
    integer kk;

    wire [8:0] kcnt = p / 9'd3;
    wire [8:0] jct = p % 9'd3;
    wire [6:0] k_cnt = kcnt[6:0];
    wire [1:0] j_cnt = jct[1:0];

    wire [11:0] a0 = a_arr[j_cnt][2 * k_cnt];
    wire [11:0] a1 = a_arr[j_cnt][2 * k_cnt + 1];
    wire [11:0] b0 = b_arr[j_cnt][2 * k_cnt];
    wire [11:0] b1 = b_arr[j_cnt][2 * k_cnt + 1];

    wire [11:0] gv;
    gamma_rom u_gamma (
        .idx(k_cnt),
        .gamma(gv)
    );

    wire [11:0] c0;
    wire [11:0] c1;
    basemul_core u_core (
        .a0(a0),
        .a1(a1),
        .b0(b0),
        .b1(b1),
        .gamma(gv),
        .c0(c0),
        .c1(c1)
    );

    wire [12:0] nacc0 = (j_cnt == 2'd0) ? {1'b0, c0} : ({1'b0, acc0} + {1'b0, c0});
    wire [12:0] nacc0r = (nacc0 >= Q) ? (nacc0 - Q) : nacc0;
    wire [12:0] nacc1 = (j_cnt == 2'd0) ? {1'b0, c1} : ({1'b0, acc1} + {1'b0, c1});
    wire [12:0] nacc1r = (nacc1 >= Q) ? (nacc1 - Q) : nacc1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            p <= 9'd0;
            acc0 <= 12'd0;
            acc1 <= 12'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        p <= 9'd0;
                        acc0 <= 12'd0;
                        acc1 <= 12'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    acc0 <= nacc0r[11:0];
                    acc1 <= nacc1r[11:0];
                    if (j_cnt == 2'd2) begin
                        c_arr[{2'd0, k_cnt, 1'b0}] <= nacc0r[11:0];
                        c_arr[{2'd0, k_cnt, 1'b0} + 10'd1] <= nacc1r[11:0];
                    end
                    if (p == 9'd383) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        p <= p + 9'd1;
                    end
                end
            endcase
        end
    end

    integer jl;
    integer kl;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
        end else if (start && phase == PHASE_IDLE) begin
            for (jl = 0; jl < 3; jl = jl + 1) begin
                for (kl = 0; kl < 256; kl = kl + 1) begin
                    a_arr[jl][kl] = a_in[12 * (256 * jl + kl) +: 12];
                end
            end
            for (jl = 0; jl < 3; jl = jl + 1) begin
                for (kl = 0; kl < 256; kl = kl + 1) begin
                    b_arr[jl][kl] = b_in[12 * (256 * jl + kl) +: 12];
                end
            end
        end
    end

    genvar gg;
    generate
        for (gg = 0; gg < 256; gg = gg + 1) begin : g_out
            assign c_out[12 * gg +: 12] = c_arr[gg];
        end
    endgenerate
endmodule
