module mldsa_sign (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [32255:0] sk_in,
    input  wire [511:0]  mu_b,
    input  wire [255:0]  rnd_in,
    output reg           busy,
    output reg           done,
    output wire          error,
    output wire [26471:0] sig_out,

    output wire [3:0]   shk_req,
    output wire [71:0]  shk_cfg,
    input  wire [3:0]   shk_ready,
    input  wire [3:0]   shk_done,
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
    localparam BETA = 23'd196;
    localparam OMEGA = 6'd55;

    localparam PHASE_IDLE   = 5'd0;
    localparam PHASE_DECS1  = 5'd1;
    localparam PHASE_DECS2  = 5'd2;
    localparam PHASE_DECT0  = 5'd3;
    localparam PHASE_NTT_S1 = 5'd4;
    localparam PHASE_NTT_S2 = 5'd5;
    localparam PHASE_NTT_T0 = 5'd6;
    localparam PHASE_A      = 5'd7;
    localparam PHASE_RHOPP  = 5'd8;
    localparam PHASE_EM     = 5'd9;
    localparam PHASE_Y_HAT  = 5'd10;
    localparam PHASE_MM     = 5'd11;
    localparam PHASE_INTTW  = 5'd12;
    localparam PHASE_W1     = 5'd13;
    localparam PHASE_W1T    = 5'd14;
    localparam PHASE_CTIL   = 5'd15;
    localparam PHASE_C      = 5'd16;
    localparam PHASE_C_HAT  = 5'd17;
    localparam PHASE_CS1    = 5'd18;
    localparam PHASE_CS1I   = 5'd19;
    localparam PHASE_CS2    = 5'd20;
    localparam PHASE_CS2I   = 5'd21;
    localparam PHASE_ZZ     = 5'd22;
    localparam PHASE_WCS2   = 5'd23;
    localparam PHASE_CT0    = 5'd24;
    localparam PHASE_CT0I   = 5'd25;
    localparam PHASE_HINT   = 5'd26;
    localparam PHASE_ZADJ   = 5'd27;
    localparam PHASE_OUTZ   = 5'd28;
    localparam PHASE_OUTH   = 5'd29;
    localparam PHASE_DONE   = 5'd30;
    localparam PHASE_RETRY  = 5'd31;

    reg [4:0] phase;
    reg [7:0] cnt;
    reg [10:0] cnt2;
    reg [15:0] kappa_r;
    reg [7:0] hcut_pos;
    reg fail_r;
    reg [6:0] wgt_r;
    reg [7:0] sk_byte [0:4031];
    reg [22:0] s1_arr [0:1279];
    reg [22:0] s2_arr [0:1535];
    reg [22:0] t0_arr [0:1535];
    reg [22:0] s1_hat [0:1279];
    reg [22:0] s2_hat [0:1535];
    reg [22:0] t0_hat [0:1535];
    reg [22:0] a_hat [0:29][0:255];
    reg [7:0] rhopp_r [0:63];
    reg [22:0] y_arr [0:1279];
    reg [22:0] y_hat [0:1279];
    reg [22:0] w_hat [0:1535];
    reg [22:0] w_arr [0:1535];
    reg [3:0] w1_arr [0:1535];
    reg [7:0] w1_byte [0:767];
    reg [7:0] c_tilde [0:47];
    reg [22:0] c_arr [0:255];
    reg [22:0] c_hat [0:255];
    reg [22:0] cs1p [0:1279];
    reg [22:0] cs1_arr [0:1279];
    reg [22:0] cs2p [0:1535];
    reg [22:0] cs2_arr [0:1535];
    reg [22:0] ct0p [0:1535];
    reg [22:0] ct0_arr [0:1535];
    reg [22:0] zz_arr [0:1279];
    reg [22:0] zz_enc [0:1279];
    reg [22:0] wcs2_arr [0:1535];
    reg hh_bool [0:1535];
    reg [7:0] sig_byte [0:3308];

    integer bb;
    integer pkb;
    integer pkk;
    reg [7:0] ct_b [0:135];
    integer cbb2;
    integer gbv2;

    reg pk_start;
    reg pk_mode;
    reg [4:0] pk_d;
    wire pk_done;
    wire [5887:0] pk_coeffs;
    wire [5119:0] pk_bytes;
    wire [5887:0] pk_coeffs_in;
    wire [5119:0] pk_bytes_in;
    reg [7:0] pk_src [0:639];

    reg em_start;
    wire em_done;
    wire [5887:0] em_coeffs;
    wire em_req;
    wire [17:0] em_cfg;
    wire em_bv;
    wire [1343:0] em_bd;
    wire em_or;

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

    reg rp_start;
    wire rp_done;
    wire rp_osync;
    wire [1087:0] rp_out;
    wire rp_req;
    wire rp_bv;
    wire [1343:0] rp_bd;
    wire rp_or;
    wire [3:0] rp_idx;

    reg ct_start;
    wire ct_done;
    wire [1087:0] ct_out;
    wire ct_req;
    wire ct_bv;
    wire [1343:0] ct_bd;
    wire ct_or;
    wire [3:0] ct_idx;
    wire ct_osync;

    wire rp_go = (phase == PHASE_RHOPP);
    wire ct_go = (phase == PHASE_CTIL);
    reg cli_start;
    wire [17:0] cli_cfg = rp_go ? {4'd1, 2'd1, 12'd128} : {4'd1, 2'd1, 12'd832};
    wire [3:0] cli_nblk = rp_go ? 4'd1 : 4'd7;
    wire [1343:0] cli_msg;

    pack_dsa u_pk (
        .clk(clk), .rst_n(rst_n), .start(pk_start), .mode(pk_mode), .d(pk_d),
        .coeffs_in(pk_coeffs_in), .bytes_in(pk_bytes_in),
        .busy(), .done(pk_done), .coeffs_out(pk_coeffs), .bytes_out(pk_bytes)
    );

    expand_mask u_em (
        .clk(clk), .rst_n(rst_n), .start(em_start),
        .rho(rhopp_w), .mu({8'd0, kappa_r[7:0]} + {8'd0, em_i}),
        .busy(), .done(em_done), .coeffs(em_coeffs),
        .shk_req(em_req), .shk_cfg(em_cfg),
        .shk_ready(shk_ready[3]), .shk_done(shk_done[3]),
        .shk_blk_valid(em_bv), .shk_blk_ready(shk_blk_ready), .shk_blk_data(em_bd),
        .shk_out_valid(shk_out_valid), .shk_out_ready(em_or), .shk_out_data(shk_out_data)
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

    engine_client #(.NBLK_W(4)) cli (
        .clk(clk), .rst_n(rst_n),
        .start(cli_start), .cfg(cli_cfg), .nblk(cli_nblk),
        .msg_blk(cli_msg),
        .req_ready(shk_ready[0]), .blk_ready(shk_blk_ready), .out_valid(shk_out_valid), .done(shk_done[0]),
        .req_valid(rp_req), .blk_valid(rp_bv), .blk_data(rp_bd), .out_ready(rp_or), .blk_idx(rp_idx), .out_sync(rp_osync)
    );
    assign rp_done = shk_done[0];
    assign rp_out = shk_out_data[1087:0];
    assign ct_req = rp_req;
    assign ct_bv = rp_bv;
    assign ct_bd = rp_bd;
    assign ct_or = rp_or;
    assign ct_idx = rp_idx;
    assign ct_osync = rp_osync;
    assign ct_done = shk_done[0];
    assign ct_out = shk_out_data[1087:0];

    wire [7:0] a_row7 = cnt / 8'd5;
    wire [7:0] a_col7 = cnt % 8'd5;
    wire [2:0] a_row = a_row7[2:0];
    wire [2:0] a_col = a_col7[2:0];
    wire [7:0] em_i = cnt[7:0];

    wire [255:0] rho_w;
    generate
        for (genvar rb = 0; rb < 32; rb = rb + 1) begin : g_rho
            assign rho_w[8*rb +: 8] = sk_byte[31 - rb];
        end
    endgenerate
    wire [511:0] rhopp_w;
    generate
        for (genvar pb2 = 0; pb2 < 64; pb2 = pb2 + 1) begin : g_rhopp
            assign rhopp_w[8*pb2 +: 8] = rhopp_r[63 - pb2];
        end
    endgenerate
    wire [383:0] ctilde_w;
    generate
        for (genvar cb = 0; cb < 48; cb = cb + 1) begin : g_ctil
            assign ctilde_w[8*cb +: 8] = c_tilde[47 - cb];
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
        for (pkb = 0; pkb < 640; pkb = pkb + 1) begin
            pkk = 639 - pkb;
            case (phase)
                PHASE_DECS1: pk_src[pkb] = (pkk < 128) ? sk_byte[128 + cnt*128 + pkk] : 8'd0;
                PHASE_DECS2: pk_src[pkb] = (pkk < 128) ? sk_byte[768 + cnt*128 + pkk] : 8'd0;
                PHASE_DECT0: pk_src[pkb] = (pkk < 416) ? sk_byte[1536 + cnt*416 + pkk] : 8'd0;
                PHASE_W1T:   pk_src[pkb] = (pkk < 128) ? w1_byte[cnt*128 + pkk] : 8'd0;
                default:     pk_src[pkb] = 8'd0;
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

    function [22:0] qadd;
        input [23:0] a;
        input [23:0] b;
        reg [24:0] s;
        begin
            s = {1'b0, a} + {1'b0, b};
            qadd = (s >= {2'd0, Q}) ? (s[22:0] - Q) : s[22:0];
        end
    endfunction

    function [22:0] qsub;
        input [23:0] a;
        input [23:0] b;
        reg [24:0] d;
        reg [23:0] db;
        begin
            db = {1'b0, Q} - {1'b0, b[22:0]};
            d = {1'b0, a} + db;
            qsub = (d >= {2'd0, Q}) ? (d[22:0] - Q) : d[22:0];
        end
    endfunction

    function [3:0] highbits;
        input [22:0] x;
        reg [22:0] r0;
        reg [3:0] r1;
        begin
            if (x >= 23'd7856640) r1 = 4'd15;
            else if (x >= 23'd7332864) r1 = 4'd14;
            else if (x >= 23'd6809088) r1 = 4'd13;
            else if (x >= 23'd6285312) r1 = 4'd12;
            else if (x >= 23'd5761536) r1 = 4'd11;
            else if (x >= 23'd5237760) r1 = 4'd10;
            else if (x >= 23'd4713984) r1 = 4'd9;
            else if (x >= 23'd4190208) r1 = 4'd8;
            else if (x >= 23'd3666432) r1 = 4'd7;
            else if (x >= 23'd3142656) r1 = 4'd6;
            else if (x >= 23'd2618880) r1 = 4'd5;
            else if (x >= 23'd2095104) r1 = 4'd4;
            else if (x >= 23'd1571328) r1 = 4'd3;
            else if (x >= 23'd1047552) r1 = 4'd2;
            else if (x >= 23'd523776) r1 = 4'd1;
            else r1 = 4'd0;
            r0 = x - (r1 * 23'd523776);
            if (r0 > 23'd261888) begin
                if (r1 == 4'd15) r1 = 4'd0;
                else r1 = r1 + 1'b1;
            end
            highbits = r1;
        end
    endfunction

    wire [22:0] cs1_prod = barrett23(c_hat[cnt2[7:0]] * s1_hat[cnt2]);
    wire [22:0] cs2_prod = barrett23(c_hat[cnt2[7:0]] * s2_hat[cnt2]);
    wire [22:0] ct0_prod = barrett23(c_hat[cnt2[7:0]] * t0_hat[cnt2]);

    wire [22:0] zz_sum = qadd({1'b0, y_arr[cnt2]}, {1'b0, cs1_arr[cnt2]});
    wire [22:0] zz_cen = (zz_sum > 23'd4190208) ? qsub({1'b0, 23'd8380417}, {1'b0, zz_sum}) : zz_sum;
    wire zz_ok = (zz_cen < 23'd524092);

    wire [22:0] wcs2_sub = qsub({1'b0, w_arr[cnt2]}, {1'b0, cs2_arr[cnt2]});
    wire [22:0] wcs2_mod = wcs2_sub % 23'd523776;
    wire [22:0] wcs2_r0a = (wcs2_mod > 23'd261888) ? (23'd523776 - wcs2_mod) : wcs2_mod;
    wire wcs2_ok = (wcs2_r0a < 23'd261692);

    wire [22:0] wcs2p_sum = qadd({1'b0, wcs2_arr[cnt2]}, {1'b0, ct0_arr[cnt2]});
    wire [3:0] h_a = highbits(wcs2_arr[cnt2]);
    wire [3:0] h_b = highbits(wcs2p_sum);
    wire hh_v = (h_a != h_b);
    wire [22:0] ct0_cen = (ct0_arr[cnt2] > 23'd4190208) ? qsub({1'b0, 23'd8380417}, {1'b0, ct0_arr[cnt2]}) : ct0_arr[cnt2];
    wire ct0_ok = (ct0_cen < 23'd261888);

    wire [22:0] zz_enc_c = (zz_arr[cnt2] <= GAMMA1) ? (GAMMA1 - zz_arr[cnt2]) : (Q + GAMMA1 - zz_arr[cnt2]);

    generate
        for (genvar gk = 0; gk < 256; gk = gk + 1) begin : g_pkci
            assign pk_coeffs_in[23*gk +: 23] =
                (phase == PHASE_OUTZ) ? zz_enc[{cnt[2:0], gk[7:0]}] :
                (phase == PHASE_W1T)  ? {19'd0, w1_arr[{cnt[2:0], gk[7:0]}]} :
                23'd0;
        end
    endgenerate

    wire [5887:0] ntt_in_comb;
    generate
        for (genvar gn = 0; gn < 256; gn = gn + 1) begin : g_nttin
            assign ntt_in_comb[23*gn +: 23] =
                (phase == PHASE_NTT_S1) ? s1_arr[{cnt[2:0], gn[7:0]}] :
                (phase == PHASE_NTT_S2) ? s2_arr[{cnt[2:0], gn[7:0]}] :
                (phase == PHASE_NTT_T0) ? t0_arr[{cnt[2:0], gn[7:0]}] :
                (phase == PHASE_Y_HAT)  ? y_arr[{cnt[2:0], gn[7:0]}] :
                                          c_arr[gn];
        end
    endgenerate
    assign ntt_in = ntt_in_comb;

    wire [5887:0] inv_in_comb;
    generate
        for (genvar gv = 0; gv < 256; gv = gv + 1) begin : g_invin
            assign inv_in_comb[23*gv +: 23] =
                (phase == PHASE_INTTW) ? w_hat[{cnt[2:0], gv[7:0]}] :
                (phase == PHASE_CS1I)  ? cs1p[{cnt[2:0], gv[7:0]}] :
                (phase == PHASE_CS2I)  ? cs2p[{cnt[2:0], gv[7:0]}] :
                                         ct0p[{cnt[2:0], gv[7:0]}];
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
                assign mm_b[23*(256*gbi+gbk) +: 23] = y_hat[256*gbi + gbk];
            end
        end
    endgenerate

    always @(*) begin
        for (cbb2 = 0; cbb2 < 136; cbb2 = cbb2 + 1) begin
            gbv2 = {4'd0, ct_idx} * 12'd136 + cbb2;
            if (gbv2 < 64) begin
                ct_b[cbb2] = mu_b_r[8*gbv2 +: 8];
            end else if (gbv2 < 832) begin
                ct_b[cbb2] = w1_byte[gbv2 - 64];
            end else begin
                ct_b[cbb2] = 8'd0;
            end
        end
    end
    wire [1087:0] ct_msg;
    generate
        for (genvar tj = 0; tj < 136; tj = tj + 1) begin : g_ctmsg
            assign ct_msg[8*tj +: 8] = ct_b[135 - tj];
        end
    endgenerate

    reg [7:0] rpp_b [0:135];
    integer rpb;
    always @(*) begin
        for (rpb = 0; rpb < 136; rpb = rpb + 1) begin
            if (rpb < 32) rpp_b[rpb] = sk_byte[32 + rpb];
            else if (rpb < 64) rpp_b[rpb] = rnd_in[8*(rpb-32) +: 8];
            else if (rpb < 128) rpp_b[rpb] = mu_b_r[8*(rpb-64) +: 8];
            else rpp_b[rpb] = 8'd0;
        end
    end
    wire [1087:0] rpp_msg;
    generate
        for (genvar rj = 0; rj < 136; rj = rj + 1) begin : g_rppmsg
            assign rpp_msg[8*rj +: 8] = rpp_b[135 - rj];
        end
    endgenerate
    assign cli_msg = rp_go ? ({256'b0, rpp_msg}) : ({256'b0, ct_msg});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            cnt <= 8'd0;
            cnt2 <= 11'd0;
            kappa_r <= 16'd0;
            hcut_pos <= 8'd0;
            fail_r <= 1'b0;
            wgt_r <= 7'd0;
            pk_start <= 1'b0;
            pk_mode <= 1'b0;
            pk_d <= 5'd0;
            ntt_start <= 1'b0;
            inv_start <= 1'b0;
            mm_start <= 1'b0;
            rntt_start <= 1'b0;
            sib_start <= 1'b0;
            em_start <= 1'b0;
            cli_start <= 1'b0;
        end else begin
            done <= 1'b0;
            pk_start <= 1'b0;
            ntt_start <= 1'b0;
            inv_start <= 1'b0;
            mm_start <= 1'b0;
            rntt_start <= 1'b0;
            sib_start <= 1'b0;
            em_start <= 1'b0;
            cli_start <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        for (bb = 0; bb < 4032; bb = bb + 1) begin
                            sk_byte[bb] = sk_in[32255 - 8*bb -: 8];
                        end
                        for (bb = 0; bb < 3309; bb = bb + 1) begin
                            sig_byte[bb] = 8'd0;
                        end
                        cnt <= 8'd0;
                        cnt2 <= 11'd0;
                        kappa_r <= 16'd0;
                        fail_r <= 1'b0;
                        wgt_r <= 7'd0;
                        busy <= 1'b1;
                        phase <= PHASE_DECS1;
                        pk_start <= 1'b1;
                        pk_mode <= 1'b1;
                        pk_d <= 5'd4;
                    end
                end
                PHASE_DECS1: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            s1_arr[{cnt[2:0], bb[7:0]}] <=
                                (pk_coeffs[23*bb +: 4] <= 4'd4) ?
                                ({19'd0, 4'd4} - {19'd0, pk_coeffs[23*bb +: 4]}) :
                                (Q - ({19'd0, pk_coeffs[23*bb +: 4]} - {19'd0, 4'd4}));
                        end
                        if (cnt == 8'd4) begin
                            cnt <= 8'd0;
                            phase <= PHASE_DECS2;
                            pk_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_DECS2: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            s2_arr[{cnt[2:0], bb[7:0]}] <=
                                (pk_coeffs[23*bb +: 4] <= 4'd4) ?
                                ({19'd0, 4'd4} - {19'd0, pk_coeffs[23*bb +: 4]}) :
                                (Q - ({19'd0, pk_coeffs[23*bb +: 4]} - {19'd0, 4'd4}));
                        end
                        if (cnt == 8'd5) begin
                            cnt <= 8'd0;
                            phase <= PHASE_DECT0;
                            pk_start <= 1'b1;
                            pk_d <= 5'd13;
                        end else begin
                            cnt <= cnt + 8'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_DECT0: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            t0_arr[{cnt[2:0], bb[7:0]}] <=
                                (pk_coeffs[23*bb +: 13] <= 13'd4096) ?
                                ({10'd0, 13'd4096} - {10'd0, pk_coeffs[23*bb +: 13]}) :
                                (Q - ({10'd0, pk_coeffs[23*bb +: 13]} - {10'd0, 13'd4096}));
                        end
                        if (cnt == 8'd5) begin
                            cnt <= 8'd0;
                            phase <= PHASE_NTT_S1;
                            ntt_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_NTT_S1: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            s1_hat[{cnt[2:0], bb[7:0]}] <= ntt_out[23*bb +: 23];
                        end
                        if (cnt == 8'd4) begin
                            cnt <= 8'd0;
                            phase <= PHASE_NTT_S2;
                            ntt_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_NTT_S2: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            s2_hat[{cnt[2:0], bb[7:0]}] <= ntt_out[23*bb +: 23];
                        end
                        if (cnt == 8'd5) begin
                            cnt <= 8'd0;
                            phase <= PHASE_NTT_T0;
                            ntt_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_NTT_T0: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            t0_hat[{cnt[2:0], bb[7:0]}] <= ntt_out[23*bb +: 23];
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
                            cnt <= 8'd0;
                            phase <= PHASE_RHOPP;
                            cli_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            rntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_RHOPP: begin
                    if (rp_osync) begin
                        for (bb = 0; bb < 64; bb = bb + 1) begin
                            rhopp_r[bb] <= rp_out[1087 - 8*bb -: 8];
                        end
                    end
                    if (rp_done) begin
                        cnt <= 8'd0;
                        phase <= PHASE_EM;
                        em_start <= 1'b1;
                    end
                end
                PHASE_EM: begin
                    if (em_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            y_arr[cnt*256 + bb] <= em_coeffs[23*bb +: 23];
                        end
                        if (cnt == 8'd4) begin
                            cnt <= 8'd0;
                            phase <= PHASE_Y_HAT;
                            ntt_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            em_start <= 1'b1;
                        end
                    end
                end
                PHASE_Y_HAT: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            y_hat[cnt*256 + bb] <= ntt_out[23*bb +: 23];
                        end
                        if (cnt == 8'd4) begin
                            cnt <= 8'd0;
                            phase <= PHASE_MM;
                            mm_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_MM: begin
                    if (mm_done) begin
                        for (bb = 0; bb < 1536; bb = bb + 1) begin
                            w_hat[bb] = mm_c[23*bb +: 23];
                        end
                        cnt <= 8'd0;
                        phase <= PHASE_INTTW;
                        inv_start <= 1'b1;
                    end
                end
                PHASE_INTTW: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            w_arr[cnt*256 + bb] <= inv_out[23*bb +: 23];
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
                    w1_arr[cnt2] <= highbits(w_arr[cnt2]);
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
                            w1_byte[cnt*128 + bb] <= pk_bytes[5119 - 8*bb -: 8];
                        end
                        if (cnt == 8'd5) begin
                            phase <= PHASE_CTIL;
                            cli_start <= 1'b1;
                        end else begin
                            cnt <= cnt + 8'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_CTIL: begin
                    if (ct_osync) begin
                        for (bb = 0; bb < 48; bb = bb + 1) begin
                            c_tilde[bb] <= ct_out[1087 - 8*bb -: 8];
                        end
                    end
                    if (ct_done) begin
                        phase <= PHASE_C;
                        sib_start <= 1'b1;
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
                        cnt2 <= 11'd0;
                        phase <= PHASE_CS1;
                    end
                end
                PHASE_CS1: begin
                    cs1p[cnt2] <= cs1_prod;
                    if (cnt2 == 11'd1279) begin
                        cnt <= 8'd0;
                        phase <= PHASE_CS1I;
                        inv_start <= 1'b1;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_CS1I: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            cs1_arr[cnt*256 + bb] <= inv_out[23*bb +: 23];
                        end
                        if (cnt == 8'd4) begin
                            cnt2 <= 11'd0;
                            phase <= PHASE_CS2;
                        end else begin
                            cnt <= cnt + 8'd1;
                            inv_start <= 1'b1;
                        end
                    end
                end
                PHASE_CS2: begin
                    cs2p[cnt2] <= cs2_prod;
                    if (cnt2 == 11'd1535) begin
                        cnt <= 8'd0;
                        phase <= PHASE_CS2I;
                        inv_start <= 1'b1;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_CS2I: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            cs2_arr[cnt*256 + bb] <= inv_out[23*bb +: 23];
                        end
                        if (cnt == 8'd5) begin
                            cnt2 <= 11'd0;
                            fail_r <= 1'b0;
                            phase <= PHASE_ZZ;
                        end else begin
                            cnt <= cnt + 8'd1;
                            inv_start <= 1'b1;
                        end
                    end
                end
                PHASE_ZZ: begin
                    zz_arr[cnt2] <= zz_sum;
                    if (!zz_ok) fail_r <= 1'b1;
                    if (cnt2 == 11'd1279) begin
                        cnt2 <= 11'd0;
                        phase <= PHASE_WCS2;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_WCS2: begin
                    wcs2_arr[cnt2] <= wcs2_sub;
                    if (!wcs2_ok) fail_r <= 1'b1;
                    if (cnt2 == 11'd1535) begin
                        cnt2 <= 11'd0;
                        phase <= PHASE_CT0;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_CT0: begin
                    ct0p[cnt2] <= ct0_prod;
                    if (cnt2 == 11'd1535) begin
                        cnt <= 8'd0;
                        phase <= PHASE_CT0I;
                        inv_start <= 1'b1;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_CT0I: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) begin
                            ct0_arr[cnt*256 + bb] <= inv_out[23*bb +: 23];
                        end
                        if (cnt == 8'd5) begin
                            cnt2 <= 11'd0;
                            wgt_r <= 7'd0;
                            phase <= PHASE_HINT;
                        end else begin
                            cnt <= cnt + 8'd1;
                            inv_start <= 1'b1;
                        end
                    end
                end
                PHASE_HINT: begin
                    hh_bool[cnt2] <= hh_v;
                    wgt_r <= wgt_r + {6'd0, hh_v};
                    if (!ct0_ok) fail_r <= 1'b1;
                    if (cnt2 == 11'd1535) begin
                        if (fail_r || wgt_r > {1'b0, OMEGA}) begin
                            phase <= PHASE_RETRY;
                        end else begin
                            cnt2 <= 11'd0;
                            phase <= PHASE_ZADJ;
                        end
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_ZADJ: begin
                    zz_enc[cnt2] <= zz_enc_c;
                    if (cnt2 == 11'd1279) begin
                        cnt <= 8'd0;
                        cnt2 <= 11'd0;
                        phase <= PHASE_OUTZ;
                        pk_start <= 1'b1;
                        pk_mode <= 1'b0;
                        pk_d <= 5'd20;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_OUTZ: begin
                    if (pk_done && cnt2 == 11'd0) begin
                        cnt2 <= 11'd1;
                    end else if (cnt2 >= 11'd1 && cnt2 <= 11'd640) begin
                        sig_byte[48 + cnt*640 + {21'd0, cnt2} - 32'd1] <= pk_bytes[5119 - 8*({21'd0, cnt2} - 32'd1) -: 8];
                        if (cnt2 == 11'd640) begin
                            cnt2 <= 11'd0;
                            if (cnt == 8'd4) begin
                                for (bb = 0; bb < 48; bb = bb + 1) begin
                                    sig_byte[bb] <= c_tilde[bb];
                                end
                                hcut_pos <= 8'd0;
                                phase <= PHASE_OUTH;
                            end else begin
                                cnt <= cnt + 8'd1;
                                pk_start <= 1'b1;
                            end
                        end else begin
                            cnt2 <= cnt2 + 11'd1;
                        end
                    end
                end
                PHASE_OUTH: begin
                    if (hh_bool[cnt2]) begin
                        sig_byte[3248 + {24'd0, hcut_pos}] <= cnt2[7:0];
                        hcut_pos <= hcut_pos + 8'd1;
                    end
                    if (cnt2[7:0] == 8'd255) begin
                        sig_byte[3248 + 55 + {29'd0, cnt2[10:8]}] <= hcut_pos + (hh_bool[cnt2] ? 8'd1 : 8'd0);
                    end
                    if (cnt2 == 11'd1535) begin
                        phase <= PHASE_DONE;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    phase <= PHASE_IDLE;
                end
                PHASE_RETRY: begin
                    kappa_r <= kappa_r + 16'd5;
                    fail_r <= 1'b0;
                    wgt_r <= 7'd0;
                    cnt <= 8'd0;
                    phase <= PHASE_EM;
                    em_start <= 1'b1;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    assign shk_req = {em_req, rntt_req, sib_req, rp_req};
    assign shk_cfg = {em_cfg, rntt_cfg, sib_cfg, cli_cfg};
    assign shk_blk_valid = rp_bv | sib_bv | rntt_bv | em_bv;
    assign shk_blk_data = ({1344{rp_bv}} & rp_bd) | ({1344{sib_bv}} & sib_bd) |
                          ({1344{rntt_bv}} & rntt_bd) | ({1344{em_bv}} & em_bd);
    assign shk_out_ready = rp_or | sib_or | rntt_or | em_or;
    assign error = 1'b0;

    genvar gsig;
    generate
        for (gsig = 0; gsig < 3309; gsig = gsig + 1) begin : g_sig
            assign sig_out[26471 - 8*gsig -: 8] = sig_byte[gsig];
        end
    endgenerate
endmodule
