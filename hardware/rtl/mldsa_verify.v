module mldsa_verify (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [15615:0] vk_in,
    input  wire [511:0]  mu_b,
    input  wire [26471:0] sig_in,
    output reg           busy,
    output reg           done,
    output reg           valid_out,

    output wire [2:0]   shk_req,
    output wire [53:0]  shk_cfg,
    input  wire [2:0]   shk_ready,
    input  wire [2:0]   shk_done,
    output wire         shk_blk_valid,
    input  wire         shk_blk_ready,
    output wire [1343:0] shk_blk_data,
    input  wire         shk_out_valid,
    output wire         shk_out_ready,
    input  wire [1343:0] shk_out_data
);
    localparam Q = 23'd8380417;
    localparam GAMMA1 = 23'd524288;
    localparam TWO_GAMMA2 = 23'd523776;
    localparam GAMMA2 = 23'd261888;
    localparam T2 = 23'd523776;

    localparam PHASE_IDLE = 5'd0;
    localparam PHASE_PT1 = 5'd1;
    localparam PHASE_PZ = 5'd2;
    localparam PHASE_PZADJ = 5'd3;
    localparam PHASE_H = 5'd4;
    localparam PHASE_T12D = 5'd5;
    localparam PHASE_NTT_T12D = 5'd6;
    localparam PHASE_A = 5'd7;
    localparam PHASE_C = 5'd8;
    localparam PHASE_C_HAT = 5'd9;
    localparam PHASE_Z_HAT = 5'd10;
    localparam PHASE_WH = 5'd11;
    localparam PHASE_WH2 = 5'd12;
    localparam PHASE_WA = 5'd13;
    localparam PHASE_W1 = 5'd14;
    localparam PHASE_W1T = 5'd15;
    localparam PHASE_CTIL = 5'd16;
    localparam PHASE_CMP = 5'd17;

    reg [4:0] phase;
    reg [7:0] cnt;
    reg [10:0] cnt2;
    reg [6:0] hidx;
    reg [3:0] ct_blk;
    reg ct_need_d1;
    reg [7:0] vk_byte [0:1951];
    reg [7:0] sig_byte [0:3308];
    reg [9:0] t1_arr [0:1535];
    reg [22:0] z_raw [0:1279];
    reg [22:0] z_arr [0:1279];
    reg [22:0] t1_2d_arr [0:1535];
    reg [22:0] t1_2d_hat [0:1535];
    reg [22:0] a_hat [0:29][0:255];
    reg [22:0] c_arr [0:255];
    reg [22:0] c_hat [0:255];
    reg [22:0] z_hat [0:4][0:255];
    reg [22:0] az_arr [0:1535];
    reg [22:0] w_hat [0:1535];
    reg [22:0] w_approx [0:1535];
    reg [3:0] w1_arr [0:1535];
    reg [7:0] w1_byte [0:767];
    reg [7:0] ctil [0:47];
    reg h_bool [0:1535];

    wire [7:0] hcut [0:5];
    generate
        for (genvar hc = 0; hc < 6; hc = hc + 1) begin : g_hcut
            assign hcut[hc] = sig_byte[3303 + hc];
        end
    endgenerate
    wire [7:0] hidx7 = {1'b0, hidx[6:0]};
    wire [2:0] hrow = (hidx7 >= hcut[4]) ? 3'd5 : (hidx7 >= hcut[3]) ? 3'd4 : (hidx7 >= hcut[2]) ? 3'd3 : (hidx7 >= hcut[1]) ? 3'd2 : (hidx7 >= hcut[0]) ? 3'd1 : 3'd0;

    integer bb;
    integer pkb;
    integer pkk;
    integer cbb;
    integer gbv;

    reg pk_start;
    reg pk_mode;
    reg [4:0] pk_d;
    wire pk_done;
    wire [5887:0] pk_coeffs;
    wire [5119:0] pk_bytes;
    wire [5887:0] pk_coeffs_in;
    wire [5119:0] pk_bytes_in;
    reg [7:0] pk_src [0:639];

    reg sib_start;
    wire sib_done;
    wire [5887:0] sib_coeffs;
    wire sib_req;
    wire [17:0] sib_cfg;
    wire sib_bv;
    wire [1343:0] sib_bd;
    wire sib_or;

    reg ntt_start;
    wire ntt_done;
    wire [5887:0] ntt_out;
    wire [5887:0] ntt_in;

    reg inv_start;
    wire inv_done;
    wire [5887:0] inv_out;
    wire [5887:0] inv_in;

    reg mm_start;
    wire mm_done;
    wire [35327:0] mm_c;
    wire [176639:0] mm_a;
    wire [29439:0] mm_b;

    reg rntt_start;
    wire rntt_done;
    wire [5887:0] rntt_coeffs;
    wire rntt_req;
    wire [17:0] rntt_cfg;
    wire rntt_bv;
    wire [1343:0] rntt_bd;
    wire rntt_or;

    reg ct_start;
    wire ct_done;
    wire [1087:0] ct_out;
    wire [1087:0] ct_msg;
    reg [7:0] ct_b [0:135];
    wire ct_req;
    wire ct_bv;
    wire [1343:0] ct_bd;
    wire ct_or;
    wire [3:0] ct_idx;
    wire ct_osync;
    assign ct_done = shk_done[0];
    assign ct_out = shk_out_data[1087:0];

    wire [255:0] rho_w;
    generate
        for (genvar rb = 0; rb < 32; rb = rb + 1) begin : g_rho
            assign rho_w[8*rb +: 8] = vk_byte[31 - rb];
        end
    endgenerate
    wire [383:0] ctilde_w;
    generate
        for (genvar cb = 0; cb < 48; cb = cb + 1) begin : g_ctil
            assign ctilde_w[8*cb +: 8] = sig_byte[47 - cb];
        end
    endgenerate

    pack_dsa u_pk (
        .clk(clk), .rst_n(rst_n), .start(pk_start), .mode(pk_mode), .d(pk_d),
        .coeffs_in(pk_coeffs_in), .bytes_in(pk_bytes_in),
        .busy(), .done(pk_done), .coeffs_out(pk_coeffs), .bytes_out(pk_bytes)
    );

    sample_in_ball u_sib (
        .clk(clk), .rst_n(rst_n), .start(sib_start), .ctilde(ctilde_w),
        .busy(), .done(sib_done), .error(), .coeffs(sib_coeffs),
        .shk_req(sib_req), .shk_cfg(sib_cfg),
        .shk_ready(shk_ready[1]), .shk_done(shk_done[1]),
        .shk_blk_valid(sib_bv), .shk_blk_ready(shk_blk_ready), .shk_blk_data(sib_bd),
        .shk_out_valid(shk_out_valid), .shk_out_ready(sib_or), .shk_out_data(shk_out_data)
    );

    ntt_dsa u_ntt (
        .clk(clk), .rst_n(rst_n), .start(ntt_start), .coeffs_in(ntt_in),
        .busy(), .done(ntt_done), .coeffs_out(ntt_out)
    );

    invntt_dsa u_inv (
        .clk(clk), .rst_n(rst_n), .start(inv_start), .coeffs_in(inv_in),
        .busy(), .done(inv_done), .coeffs_out(inv_out)
    );

    matmul_dsa u_mm (
        .clk(clk), .rst_n(rst_n), .start(mm_start), .a_in(mm_a), .b_in(mm_b),
        .busy(), .done(mm_done), .c_out(mm_c)
    );

    rej_ntt u_rntt (
        .clk(clk), .rst_n(rst_n), .start(rntt_start), .rho(rho_w),
        .s({5'd0, a_col}), .r({5'd0, a_row}),
        .busy(), .done(rntt_done), .error(), .coeffs(rntt_coeffs),
        .shk_req(rntt_req), .shk_cfg(rntt_cfg),
        .shk_ready(shk_ready[2]), .shk_done(shk_done[2]),
        .shk_blk_valid(rntt_bv), .shk_blk_ready(shk_blk_ready), .shk_blk_data(rntt_bd),
        .shk_out_valid(shk_out_valid), .shk_out_ready(rntt_or), .shk_out_data(shk_out_data)
    );

    engine_client #(.NBLK_W(4)) shk_cli (
        .clk(clk), .rst_n(rst_n),
        .start(ct_start), .cfg({4'd1, 2'd1, 12'd832}), .nblk(4'd7),
        .msg_blk({256'b0, ct_msg}),
        .req_ready(shk_ready[0]), .blk_ready(shk_blk_ready), .out_valid(shk_out_valid), .done(shk_done[0]),
        .req_valid(ct_req), .blk_valid(ct_bv), .blk_data(ct_bd), .out_ready(ct_or), .blk_idx(ct_idx), .out_sync(ct_osync)
    );

    wire [7:0] a_row7 = cnt / 8'd5;
    wire [7:0] a_col7 = cnt % 8'd5;
    wire [2:0] a_row = a_row7[2:0];
    wire [2:0] a_col = a_col7[2:0];
    wire [11:0] hidx12 = 12'd3248 + {5'd0, hidx[6:0]};

    always @(*) begin
        for (pkb = 0; pkb < 640; pkb = pkb + 1) begin
            pkk = 639 - pkb;
            case (phase)
                PHASE_PT1: pk_src[pkb] = (pkk < 320) ? vk_byte[32 + cnt*320 + pkk] : 8'd0;
                PHASE_PZ:  pk_src[pkb] = (pkk < 640) ? sig_byte[48 + cnt*640 + pkk] : 8'd0;
                default:   pk_src[pkb] = 8'd0;
            endcase
        end
    end
    generate
        for (genvar pkj = 0; pkj < 640; pkj = pkj + 1) begin : g_pk
            assign pk_bytes_in[8*pkj +: 8] = pk_src[pkj];
        end
    endgenerate

    function [22:0] barrett23;
        input [45:0] x;
        reg [71:0] m72;
        reg [23:0] m;
        reg [46:0] mq, rr, rr1, rr2;
        begin
            m72 = x * 26'd33587228;
            m = m72[71:48];
            mq = m * {24'd0, Q};
            rr = {1'b0, x} - mq;
            rr1 = (rr >= {24'd0, Q}) ? rr - {24'd0, Q} : rr;
            rr2 = (rr1 >= {24'd0, Q}) ? rr1 - {24'd0, Q} : rr1;
            barrett23 = rr2[22:0];
        end
    endfunction

    wire [22:0] wh_prod = barrett23(c_hat[cnt2[7:0]] * t1_2d_hat[cnt2]);
    wire [23:0] wh_s = {1'b0, az_arr[cnt2]} + {1'b0, 23'd8380417} - {1'b0, wh_prod};
    wire [22:0] wh_fin = (wh_s >= {1'b0, 23'd8380417}) ? (wh_s[22:0] - 23'd8380417) : wh_s[22:0];

    generate
        for (genvar gk = 0; gk < 256; gk = gk + 1) begin : g_pkci
            assign pk_coeffs_in[23*gk +: 23] = {19'd0, w1_arr[256*cnt + gk]};
        end
    endgenerate

    wire [5887:0] ntt_in_comb;
    generate
        for (genvar gn = 0; gn < 256; gn = gn + 1) begin : g_nttin
            assign ntt_in_comb[23*gn +: 23] =
                (phase == PHASE_C_HAT) ? c_arr[gn] :
                (phase == PHASE_Z_HAT) ? z_arr[{cnt[2:0], gn[7:0]}] :
                                         t1_2d_arr[{cnt[2:0], gn[7:0]}];
        end
    endgenerate
    assign ntt_in = ntt_in_comb;

    wire [5887:0] inv_in_comb;
    generate
        for (genvar gv = 0; gv < 256; gv = gv + 1) begin : g_invin
            assign inv_in_comb[23*gv +: 23] = w_hat[{cnt[2:0], gv[7:0]}];
        end
    endgenerate
    assign inv_in = inv_in_comb;

    generate
        for (genvar gai = 0; gai < 30; gai = gai + 1) begin : g_mma
            for (genvar gak = 0; gak < 256; gak = gak + 1) begin : g_mmak
                assign mm_a[23*(256*gai+gak) +: 23] = a_hat[gai][gak];
            end
        end
        for (genvar gbi = 0; gbi < 5; gbi = gbi + 1) begin : g_mmb
            for (genvar gbk = 0; gbk < 256; gbk = gbk + 1) begin : g_mmbk
                assign mm_b[23*(256*gbi+gbk) +: 23] = z_hat[gbi][gbk];
            end
        end
    endgenerate

    wire [511:0] mu_b_r;
    genvar mbr;
    generate
        for (mbr = 0; mbr < 64; mbr = mbr + 1) begin : g_mubr
            assign mu_b_r[8*mbr +: 8] = mu_b[511 - 8*mbr - 7 +: 8];
        end
    endgenerate

    always @(*) begin
        for (cbb = 0; cbb < 136; cbb = cbb + 1) begin
            gbv = {4'd0, ct_idx} * 12'd136 + cbb;
            if (gbv < 64) begin
                ct_b[cbb] = mu_b_r[8*gbv +: 8];
            end else if (gbv < 832) begin
                ct_b[cbb] = w1_byte[gbv - 64];
            end else begin
                ct_b[cbb] = 8'd0;
            end
        end
    end
    generate
        for (genvar tj = 0; tj < 136; tj = tj + 1) begin : g_ctmsg
            assign ct_msg[8*tj +: 8] = ct_b[135 - tj];
        end
    endgenerate

    wire [22:0] wh_x = w_approx[cnt2];
    reg [3:0] kx;
    always @(*) begin
        if (wh_x >= 23'd7856640) kx = 4'd15;
        else if (wh_x >= 23'd7332864) kx = 4'd14;
        else if (wh_x >= 23'd6809088) kx = 4'd13;
        else if (wh_x >= 23'd6285312) kx = 4'd12;
        else if (wh_x >= 23'd5761536) kx = 4'd11;
        else if (wh_x >= 23'd5237760) kx = 4'd10;
        else if (wh_x >= 23'd4713984) kx = 4'd9;
        else if (wh_x >= 23'd4190208) kx = 4'd8;
        else if (wh_x >= 23'd3666432) kx = 4'd7;
        else if (wh_x >= 23'd3142656) kx = 4'd6;
        else if (wh_x >= 23'd2618880) kx = 4'd5;
        else if (wh_x >= 23'd2095104) kx = 4'd4;
        else if (wh_x >= 23'd1571328) kx = 4'd3;
        else if (wh_x >= 23'd1047552) kx = 4'd2;
        else if (wh_x >= 23'd523776) kx = 4'd1;
        else kx = 4'd0;
    end
    wire [22:0] kxT = kx * 23'd523776;
    wire [22:0] r0c = wh_x - kxT;
    wire is_neg = (r0c > 23'd261888);
    wire [3:0] r1e = (kx + {3'b0, is_neg}) & 4'hF;
    wire r0p = (!is_neg) && (|r0c);
    wire [3:0] w1v = h_bool[cnt2] ? (r0p ? (r1e + 4'd1) : (r1e + 4'd15)) : r1e;

    wire valid_cmp;
    wire [47:0] valid_v;
    generate
        for (genvar vc = 0; vc < 48; vc = vc + 1) begin : g_cmp
            assign valid_v[vc] = (ctil[vc] == sig_byte[vc]);
        end
    endgenerate
    assign valid_cmp = &valid_v;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            valid_out <= 1'b0;
            cnt <= 8'd0;
            cnt2 <= 11'd0;
            hidx <= 7'd0;
            pk_start <= 1'b0;
            pk_mode <= 1'b0;
            pk_d <= 5'd0;
            ntt_start <= 1'b0;
            inv_start <= 1'b0;
            mm_start <= 1'b0;
            rntt_start <= 1'b0;
            sib_start <= 1'b0;
            ct_start <= 1'b0;
        end else begin
            done <= 1'b0;
            pk_start <= 1'b0;
            ntt_start <= 1'b0;
            inv_start <= 1'b0;
            mm_start <= 1'b0;
            rntt_start <= 1'b0;
            sib_start <= 1'b0;
            ct_start <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        for (bb = 0; bb < 1952; bb = bb + 1) begin
                            vk_byte[bb] = vk_in[15615 - 8*bb -: 8];
                        end
                        for (bb = 0; bb < 3309; bb = bb + 1) begin
                            sig_byte[bb] = sig_in[26471 - 8*bb -: 8];
                        end
                        for (bb = 0; bb < 1536; bb = bb + 1) begin
                            h_bool[bb] = 1'b0;
                        end
                        cnt <= 8'd0;
                        cnt2 <= 11'd0;
                        hidx <= 7'd0;
                        busy <= 1'b1;
                        phase <= PHASE_PT1;
                        pk_start <= 1'b1;
                        pk_mode <= 1'b1;
                        pk_d <= 5'd10;
                    end
                end
                PHASE_PT1: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            t1_arr[{cnt[2:0], bb[7:0]}] <= pk_coeffs[23*bb +: 10];
                        end
                        if (cnt == 8'd5) begin
                            cnt <= 8'd0;
                            phase <= PHASE_PZ;
                            pk_start <= 1'b1;
                            pk_d <= 5'd20;
                        end else begin
                            cnt <= cnt + 8'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_PZ: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            z_raw[{cnt[2:0], bb[7:0]}] <= {3'd0, pk_coeffs[23*bb +: 20]};
                        end
                        if (cnt == 8'd4) begin
                            cnt2 <= 11'd0;
                            phase <= PHASE_PZADJ;
                        end else begin
                            cnt <= cnt + 8'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_PZADJ: begin
                    if (z_raw[cnt2] <= 23'h80000) begin
                        z_arr[cnt2] <= 23'd524288 - {3'd0, z_raw[cnt2][19:0]};
                    end else begin
                        z_arr[cnt2] <= 23'd8380417 - ({3'd0, z_raw[cnt2][19:0]} - 23'd524288);
                    end
                    if (cnt2 == 11'd1279) begin
                        hidx <= 7'd0;
                        phase <= PHASE_H;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_H: begin
                    if (hidx7 < hcut[5]) begin
                        h_bool[{hrow, sig_byte[hidx12]}] <= 1'b1;
                    end
                    if (hidx == 7'd54) begin
                        cnt2 <= 11'd0;
                        phase <= PHASE_T12D;
                    end else begin
                        hidx <= hidx + 7'd1;
                    end
                end
                PHASE_T12D: begin
                    t1_2d_arr[cnt2] <= {t1_arr[cnt2], 13'd0};
                    if (cnt2 == 11'd1535) begin
                        cnt <= 8'd0;
                        phase <= PHASE_NTT_T12D;
                        ntt_start <= 1'b1;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_NTT_T12D: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            t1_2d_hat[{cnt[2:0], bb[7:0]}] <= ntt_out[23*bb +: 23];
                        end
                        if (cnt == 8'd5) begin
                            cnt <= 8'd0;
                            phase <= PHASE_A;
                            rntt_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_A: begin
                    if (rntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            a_hat[cnt[4:0]][bb[7:0]] <= rntt_coeffs[23*bb +: 23];
                        end
                        if (cnt == 8'd29) begin
                            phase <= PHASE_C;
                            sib_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            rntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_C: begin
                    if (sib_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            c_arr[bb] <= sib_coeffs[23*bb +: 23];
                        end
                        phase <= PHASE_C_HAT;
                        ntt_start <= 1'b1;
                    end
                end
                PHASE_C_HAT: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            c_hat[bb] <= ntt_out[23*bb +: 23];
                        end
                        cnt <= 8'd0;
                        phase <= PHASE_Z_HAT;
                        ntt_start <= 1'b1;
                    end
                end
                PHASE_Z_HAT: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            z_hat[cnt[2:0]][bb[7:0]] <= ntt_out[23*bb +: 23];
                        end
                        if (cnt == 8'd4) begin
                            phase <= PHASE_WH;
                            mm_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_WH: begin
                    if (mm_done) begin
                        for (bb = 0; bb < 1536; bb = bb + 1) begin
                            az_arr[bb] = mm_c[23*bb +: 23];
                        end
                        cnt2 <= 11'd0;
                        phase <= PHASE_WH2;
                    end
                end
                PHASE_WH2: begin
                    w_hat[cnt2] <= wh_fin;
                    if (cnt2 == 11'd1535) begin
                        cnt <= 8'd0;
                        phase <= PHASE_WA;
                        inv_start <= 1'b1;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_WA: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            w_approx[{cnt[2:0], bb[7:0]}] <= inv_out[23*bb +: 23];
                        end
                        if (cnt == 8'd5) begin
                            cnt2 <= 11'd0;
                            phase <= PHASE_W1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            inv_start <= 1'b1;
                        end
                    end
                end
                PHASE_W1: begin
                    w1_arr[cnt2] <= w1v;
                    if (cnt2 == 11'd1535) begin
                        cnt <= 8'd0;
                        phase <= PHASE_W1T;
                        pk_start <= 1'b1;
                        pk_mode <= 1'b0;
                        pk_d <= 5'd4;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_W1T: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 128; bb = bb + 1) begin
                            w1_byte[128*cnt + bb] <= pk_bytes[5119 - 8*bb -: 8];
                        end
                        if (cnt == 8'd5) begin
                            phase <= PHASE_CTIL;
                            ct_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_CTIL: begin
                    if (ct_osync) begin
                        for (bb = 0; bb < 48; bb = bb + 1) begin
                            ctil[bb] <= ct_out[1087 - 8*bb -: 8];
                        end
                    end
                    if (ct_done) begin
                        phase <= PHASE_CMP;
                    end
                end
                PHASE_CMP: begin
                    valid_out <= valid_cmp;
                    busy <= 1'b0;
                    done <= 1'b1;
                    phase <= PHASE_IDLE;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    assign shk_req = {rntt_req, sib_req, ct_req};
    assign shk_cfg = {rntt_cfg, sib_cfg, {4'd1, 2'd1, 12'd832}};
    assign shk_blk_valid = ct_bv | sib_bv | rntt_bv;
    assign shk_blk_data = ({1344{ct_bv}} & ct_bd) | ({1344{sib_bv}} & sib_bd) | ({1344{rntt_bv}} & rntt_bd);
    assign shk_out_ready = ct_or | sib_or | rntt_or;
endmodule
