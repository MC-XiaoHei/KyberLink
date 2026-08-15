module kem_encaps (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [9471:0] ek_in,
    input  wire [255:0]  m,
    output reg          busy,
    output reg          done,
    output reg  [255:0]  k_out,
    output wire [8703:0] c_out,

    output wire [3:0]     shk_req,
    output wire [71:0]    shk_cfg,
    input  wire [3:0]     shk_ready,
    input  wire [3:0]     shk_done,
    output wire           shk_blk_valid,
    input  wire           shk_blk_ready,
    output wire [1343:0]  shk_blk_data,
    input  wire           shk_out_valid,
    output wire           shk_out_ready,
    input  wire  [1343:0] shk_out_data
);
    localparam Q = 12'd3329;

    localparam PHASE_IDLE = 5'd0;
    localparam PHASE_H    = 5'd1;
    localparam PHASE_G    = 5'd2;
    localparam PHASE_TH   = 5'd3;
    localparam PHASE_A    = 5'd4;
    localparam PHASE_CB   = 5'd5;
    localparam PHASE_YH   = 5'd6;
    localparam PHASE_MM   = 5'd7;
    localparam PHASE_UI   = 5'd8;
    localparam PHASE_MU   = 5'd9;
    localparam PHASE_VD   = 5'd10;
    localparam PHASE_VI   = 5'd11;
    localparam PHASE_VA   = 5'd12;
    localparam PHASE_CU   = 5'd13;
    localparam PHASE_CU2  = 5'd14;
    localparam PHASE_CV   = 5'd15;
    localparam PHASE_CV2  = 5'd16;
    localparam PHASE_DONE = 5'd17;

    reg [4:0] phase;
    reg [3:0] cnt;

    reg [255:0] r;

    reg [7:0] ek_byte [0:1183];
    reg [7:0] hek     [0:31];
    reg [7:0] c_byte  [0:1087];

    reg [11:0] th_arr[0:2][0:255];
    reg [11:0] a_arr [0:8][0:255];
    reg [11:0] y_arr [0:2][0:255];
    reg [11:0] e1_arr[0:2][0:255];
    reg [11:0] e2_arr[0:255];
    reg [11:0] yh_arr[0:2][0:255];
    reg [11:0] u_arr [0:767];
    reg [11:0] v_arr [0:255];
    reg [11:0] mu_arr[0:255];
    reg [11:0] cu_arr[0:2][0:255];

    wire h_done;
    wire [1087:0] h_out;
    reg h_start;
    wire h_req, h_bv, h_or, h_osync;
    wire [3:0] h_idx;
    wire [1343:0] h_bd;

    wire [1087:0] h_msg;
    reg [7:0] h_msg_b [0:135];
    integer hc;
    integer hidx;
    wire [10:0] h_base = {3'b0, h_idx} * 11'd136;
    always @(*) begin
        for (hc = 0; hc < 136; hc = hc + 1) begin
            hidx = {20'd0, {1'b0, h_base[10:0]} + {4'd0, hc[7:0]}};
            h_msg_b[hc] = (hidx < 12'd1184) ? ek_byte[hidx[10:0]] : 8'd0;
        end
    end
    genvar hj;
    generate
        for (hj = 0; hj < 136; hj = hj + 1) begin: hmsg
            assign h_msg[8*hj +: 8] = h_msg_b[135-hj];
        end
    endgenerate

    engine_client #(.NBLK_W(4)) u_hc (
        .clk(clk), .rst_n(rst_n),
        .start(h_start), .cfg({4'd1, 2'd2, 12'd1184}), .nblk(4'd9),
        .msg_blk({256'b0, h_msg}),
        .req_ready(shk_ready[0]), .blk_ready(shk_blk_ready),
        .out_valid(shk_out_valid), .done(shk_done[0]),
        .req_valid(h_req), .blk_valid(h_bv), .blk_data(h_bd), .out_ready(h_or), .blk_idx(h_idx),
        .out_sync(h_osync)
    );
    assign h_done = shk_done[0];
    assign h_out = shk_out_data[1087:0];

    wire g_done;
    wire [575:0] g_out;
    reg g_start;
    wire g_req, g_bv, g_or, g_osync;
    wire [1343:0] g_bd;

    engine_client #(.NBLK_W(4)) u_gc (
        .clk(clk), .rst_n(rst_n),
        .start(g_start), .cfg({4'd1, 2'd3, 12'd64}), .nblk(4'd1),
        .msg_blk({768'b0, m, hek[0], hek[1], hek[2], hek[3], hek[4], hek[5], hek[6], hek[7],
                  hek[8], hek[9], hek[10], hek[11], hek[12], hek[13], hek[14], hek[15],
                  hek[16], hek[17], hek[18], hek[19], hek[20], hek[21], hek[22], hek[23],
                  hek[24], hek[25], hek[26], hek[27], hek[28], hek[29], hek[30], hek[31],
                  64'b0}),
        .req_ready(shk_ready[1]), .blk_ready(shk_blk_ready),
        .out_valid(shk_out_valid), .done(shk_done[1]),
        .req_valid(g_req), .blk_valid(g_bv), .blk_data(g_bd), .out_ready(g_or), .blk_idx(),
        .out_sync(g_osync)
    );
    assign g_done = shk_done[1];
    assign g_out = shk_out_data[575:0];

    wire pk_done;
    wire [3071:0] pk_bytes;
    wire [3071:0] pk_coeffs;
    reg pk_start;
    reg pk_mode;
    reg [3:0] pk_d;

    wire [3071:0] pk_bytes_in;
    genvar pb;
    generate
        for (pb = 0; pb < 384; pb = pb + 1) begin: thbyte
            assign pk_bytes_in[8*pb +: 8] = ek_byte[384*cnt[1:0] + (383-pb)];
        end
    endgenerate

    pack u_pk (
        .clk(clk), .rst_n(rst_n),
        .start(pk_start), .mode(pk_mode), .d(pk_d),
        .coeffs_in(pk_coeffs),
        .bytes_in(pk_bytes_in),
        .busy(), .done(pk_done),
        .coeffs_out(pk_coeffs), .bytes_out(pk_bytes)
    );

    wire [255:0] rho;
    genvar rg;
    generate
        for (rg = 0; rg < 32; rg = rg + 1) begin: rhomap
            assign rho[8*rg +: 8] = ek_byte[1183 - rg];
        end
    endgenerate

    wire sntt_done;
    wire [3071:0] sntt_coeffs;
    reg sntt_start;
    wire sntt_req, sntt_bv, sntt_or;
    wire [17:0] sntt_cfg;
    wire [1343:0] sntt_bd;

    wire [3:0] a_row_w = cnt / 4'd3;
    wire [3:0] a_col_w = cnt % 4'd3;
    wire [1:0] a_row = a_row_w[1:0];
    wire [1:0] a_col = a_col_w[1:0];

    sample_ntt u_sntt (
        .clk(clk), .rst_n(rst_n),
        .start(sntt_start),
        .rho(rho),
        .i({6'd0, a_col}), .j({6'd0, a_row}),
        .busy(), .done(sntt_done),
        .coeffs(sntt_coeffs), .error(),
        .shk_req(sntt_req), .shk_cfg(sntt_cfg), .shk_ready(shk_ready[2]),
        .shk_done(shk_done[2]),
        .shk_blk_valid(sntt_bv), .shk_blk_ready(shk_blk_ready), .shk_blk_data(sntt_bd),
        .shk_out_valid(shk_out_valid), .shk_out_ready(sntt_or), .shk_out_data(shk_out_data)
    );

    wire cbd_done;
    wire [767:0] cbd_coeffs;
    reg cbd_start;
    wire cbd_req, cbd_bv, cbd_or;
    wire [17:0] cbd_cfg;
    wire [1343:0] cbd_bd;

    sample_cbd u_scbd (
        .clk(clk), .rst_n(rst_n),
        .start(cbd_start),
        .rho(r),
        .i({5'd0, cnt[2:0]}),
        .busy(), .done(cbd_done),
        .coeffs(cbd_coeffs),
        .shk_req(cbd_req), .shk_cfg(cbd_cfg), .shk_ready(shk_ready[3]),
        .shk_done(shk_done[3]),
        .shk_blk_valid(cbd_bv), .shk_blk_ready(shk_blk_ready), .shk_blk_data(cbd_bd),
        .shk_out_valid(shk_out_valid), .shk_out_ready(cbd_or), .shk_out_data(shk_out_data)
    );

    wire [11:0] cbd_tmp [0:255];
    genvar cg;
    generate
        for (cg = 0; cg < 256; cg = cg + 1) begin: cbdmap
            wire signed [2:0] sv = $signed(cbd_coeffs[3*cg +: 3]);
            wire signed [11:0] sex = {{9{sv[2]}}, sv};
            wire [12:0] sadd = sex + 13'd3329;
            assign cbd_tmp[cg] = sv[2] ? sadd[11:0] : sex[11:0];
        end
    endgenerate

    wire ntt_done;
    wire [3071:0] ntt_out;
    reg ntt_start;

    wire [3071:0] ntt_in;
    genvar ng;
    generate
        for (ng = 0; ng < 256; ng = ng + 1) begin: nttin
            assign ntt_in[12*ng +: 12] = y_arr[cnt[1:0]][ng];
        end
    endgenerate

    wire [2:0] e1_idx3 = cnt[2:0] - 3'd3;
    wire [1:0] e1_idx = e1_idx3[1:0];

    ntt u_ntt (
        .clk(clk), .rst_n(rst_n),
        .start(ntt_start),
        .coeffs_in(ntt_in),
        .busy(), .done(ntt_done),
        .coeffs_out(ntt_out)
    );

    wire mm_done;
    wire [9215:0] mm_c;
    reg mm_start;

    wire [27647:0] mm_a;
    wire [9215:0]  mm_b;
    genvar ga, gb;
    generate
        for (ga = 0; ga < 9; ga = ga + 1) begin: amap
            for (gb = 0; gb < 256; gb = gb + 1) begin: amapk
                assign mm_a[12*(256*ga+gb) +: 12] = a_arr[ga][gb];
            end
        end
        for (ga = 0; ga < 3; ga = ga + 1) begin: bmap
            for (gb = 0; gb < 256; gb = gb + 1) begin: bmapk
                assign mm_b[12*(256*ga+gb) +: 12] = yh_arr[ga][gb];
            end
        end
    endgenerate

    matmul u_mm (
        .clk(clk), .rst_n(rst_n),
        .start(mm_start), .mode(1'b1),
        .a_in(mm_a), .b_in(mm_b),
        .busy(), .done(mm_done),
        .c_out(mm_c)
    );

    wire inv_done;
    wire [3071:0] inv_out;
    reg inv_start;

    wire [3071:0] inv_in;
    genvar ig;
    generate
        for (ig = 0; ig < 256; ig = ig + 1) begin: invin
            assign inv_in[12*ig +: 12] = (phase == PHASE_UI) ? u_arr[256*cnt[1:0] + ig] : v_arr[ig];
        end
    endgenerate

    invntt u_inv (
        .clk(clk), .rst_n(rst_n),
        .start(inv_start),
        .coeffs_in(inv_in),
        .busy(), .done(inv_done),
        .coeffs_out(inv_out)
    );

    wire dm_done;
    wire [3071:0] dm_c;
    reg dm_start;

    wire [9215:0] dm_a;
    wire [9215:0] dm_b;
    genvar da, db;
    generate
        for (da = 0; da < 3; da = da + 1) begin: amap2
            for (db = 0; db < 256; db = db + 1) begin: amapk2
                assign dm_a[12*(256*da+db) +: 12] = th_arr[da][db];
                assign dm_b[12*(256*da+db) +: 12] = yh_arr[da][db];
            end
        end
    endgenerate

    dotmul u_dm (
        .clk(clk), .rst_n(rst_n),
        .start(dm_start),
        .a_in(dm_a), .b_in(dm_b),
        .busy(), .done(dm_done),
        .c_out(dm_c)
    );

    wire comp_done;
    wire [3071:0] comp_y;
    reg comp_start;
    reg comp_mode;
    reg [3:0] comp_d;

    wire [3071:0] comp_x;
    genvar cq;
    generate
        for (cq = 0; cq < 256; cq = cq + 1) begin: compx
            assign comp_x[12*cq +: 12] = (phase == PHASE_MU) ? {11'd0, m[248 - 8*(cq/8) + (cq%8)]}
                                     : ((phase == PHASE_CU) ? u_arr[256*cnt[1:0] + cq] : v_arr[cq]);
        end
    endgenerate

    compress u_comp (
        .clk(clk), .rst_n(rst_n),
        .start(comp_start), .mode(comp_mode), .d(comp_d),
        .x_in(comp_x),
        .busy(), .done(comp_done),
        .y_out(comp_y)
    );

    wire pk2_done;
    wire [3071:0] pk2_bytes;
    reg pk2_start;

    wire [3071:0] pk2_coeffs;
    genvar qg;
    generate
        for (qg = 0; qg < 256; qg = qg + 1) begin: pk2in
            assign pk2_coeffs[12*qg +: 12] = (phase == PHASE_CV || phase == PHASE_CV2) ? cu_arr[2][qg] : cu_arr[cnt[1:0]][qg];
        end
    endgenerate

    pack u_pk2 (
        .clk(clk), .rst_n(rst_n),
        .start(pk2_start), .mode(1'b0),
        .d((phase == PHASE_CV || phase == PHASE_CV2) ? 4'd4 : 4'd10),
        .coeffs_in(pk2_coeffs),
        .bytes_in(3072'b0),
        .busy(), .done(pk2_done),
        .coeffs_out(), .bytes_out(pk2_bytes)
    );

    integer bb;
    integer ths;
    integer thd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            k_out <= 256'd0;
            h_start <= 1'b0;
            g_start <= 1'b0;
            pk_start <= 1'b0;
            pk_mode <= 1'b0;
            pk_d <= 4'd0;
            sntt_start <= 1'b0;
            cbd_start <= 1'b0;
            ntt_start <= 1'b0;
            mm_start <= 1'b0;
            inv_start <= 1'b0;
            dm_start <= 1'b0;
            comp_start <= 1'b0;
            comp_mode <= 1'b0;
            comp_d <= 4'd0;
            pk2_start <= 1'b0;
            cnt <= 4'd0;
        end else begin
            done <= 1'b0;
            h_start <= 1'b0;
            g_start <= 1'b0;
            pk_start <= 1'b0;
            sntt_start <= 1'b0;
            cbd_start <= 1'b0;
            ntt_start <= 1'b0;
            mm_start <= 1'b0;
            inv_start <= 1'b0;
            dm_start <= 1'b0;
            comp_start <= 1'b0;
            pk2_start <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        for (bb = 0; bb < 1184; bb = bb + 1) ek_byte[bb] = ek_in[9471-8*bb -: 8];
                        h_start <= 1'b1;
                        phase <= PHASE_H;
                    end
                end
                PHASE_H: begin
                    if (h_osync) begin
                        for (bb = 0; bb < 32; bb = bb + 1) hek[bb] = h_out[1087-8*bb -: 8];
                    end
                    if (h_done) begin
                        cnt <= 4'd0;
                        g_start <= 1'b1;
                        phase <= PHASE_G;
                    end
                end
                PHASE_G: begin
                    if (g_osync) begin
                        k_out <= g_out[575:320];
                        r <= g_out[319:64];
                    end
                    if (g_done) begin
                        cnt <= 4'd0;
                        pk_mode <= 1'b1;
                        pk_d <= 4'd12;
                        pk_start <= 1'b1;
                        phase <= PHASE_TH;
                    end
                end
                PHASE_TH: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) th_arr[cnt[1:0]][bb] = pk_coeffs[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            sntt_start <= 1'b1;
                            phase <= PHASE_A;
                        end else begin
                            cnt <= cnt + 4'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_A: begin
                    if (sntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) a_arr[cnt][bb] = sntt_coeffs[12*bb +: 12];
                        if (cnt == 4'd8) begin
                            cnt <= 4'd0;
                            cbd_start <= 1'b1;
                            phase <= PHASE_CB;
                        end else begin
                            cnt <= cnt + 4'd1;
                            sntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_CB: begin
                    if (cbd_done) begin
                        if (cnt < 4'd3) begin
                            for (bb = 0; bb < 256; bb = bb + 1) y_arr[cnt[1:0]][bb] = cbd_tmp[bb];
                        end else if (cnt < 4'd6) begin
                            for (bb = 0; bb < 256; bb = bb + 1) e1_arr[e1_idx][bb] = cbd_tmp[bb];
                        end else begin
                            for (bb = 0; bb < 256; bb = bb + 1) e2_arr[bb] = cbd_tmp[bb];
                        end
                        if (cnt == 4'd6) begin
                            cnt <= 4'd0;
                            ntt_start <= 1'b1;
                            phase <= PHASE_YH;
                        end else begin
                            cnt <= cnt + 4'd1;
                            cbd_start <= 1'b1;
                        end
                    end
                end
                PHASE_YH: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) yh_arr[cnt[1:0]][bb] = ntt_out[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            mm_start <= 1'b1;
                            phase <= PHASE_MM;
                        end else begin
                            cnt <= cnt + 4'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_MM: begin
                    if (mm_done) begin
                        for (bb = 0; bb < 768; bb = bb + 1) u_arr[bb] = mm_c[12*bb +: 12];
                        cnt <= 4'd0;
                        inv_start <= 1'b1;
                        phase <= PHASE_UI;
                    end
                end
                PHASE_UI: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) u_arr[256*cnt[1:0] + bb] = inv_out[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            for (bb = 0; bb < 768; bb = bb + 1) begin
                                ths = ({19'd0, u_arr[bb]} + {19'd0, e1_arr[bb[9:8]][bb[7:0]]});
                                if (ths >= Q) begin
                                    thd = ths - {20'd0, Q};
                                    u_arr[bb] = thd[11:0];
                                end else begin
                                    u_arr[bb] = ths[11:0];
                                end
                            end
                            cnt <= 4'd0;
                            comp_mode <= 1'b1;
                            comp_d <= 4'd1;
                            comp_start <= 1'b1;
                            phase <= PHASE_MU;
                        end else begin
                            cnt <= cnt + 4'd1;
                            inv_start <= 1'b1;
                        end
                    end
                end
                PHASE_MU: begin
                    if (comp_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) mu_arr[bb] = comp_y[12*bb +: 12];
                        cnt <= 4'd0;
                        dm_start <= 1'b1;
                        phase <= PHASE_VD;
                    end
                end
                PHASE_VD: begin
                    if (dm_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) v_arr[bb] = dm_c[12*bb +: 12];
                        cnt <= 4'd0;
                        inv_start <= 1'b1;
                        phase <= PHASE_VI;
                    end
                end
                PHASE_VI: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) v_arr[bb] = inv_out[12*bb +: 12];
                        phase <= PHASE_VA;
                    end
                end
                PHASE_VA: begin
                    for (bb = 0; bb < 256; bb = bb + 1) begin
                        ths = ({20'd0, v_arr[bb]} + {20'd0, e2_arr[bb]} + {20'd0, mu_arr[bb]});
                        if (ths >= Q) begin
                            thd = ths - {20'd0, Q};
                            if (thd >= Q) thd = thd - {20'd0, Q};
                            v_arr[bb] = thd[11:0];
                        end else begin
                            v_arr[bb] = ths[11:0];
                        end
                    end
                    cnt <= 4'd0;
                    comp_mode <= 1'b0;
                    comp_d <= 4'd10;
                    comp_start <= 1'b1;
                    phase <= PHASE_CU;
                end
                PHASE_CU: begin
                    if (comp_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) cu_arr[cnt[1:0]][bb] = comp_y[12*bb +: 12];
                        pk2_start <= 1'b1;
                        phase <= PHASE_CU2;
                    end
                end
                PHASE_CU2: begin
                    if (pk2_done) begin
                        for (bb = 0; bb < 320; bb = bb + 1) c_byte[320*cnt[1:0] + bb] = pk2_bytes[3071-8*bb -: 8];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            comp_mode <= 1'b0;
                            comp_d <= 4'd4;
                            comp_start <= 1'b1;
                            phase <= PHASE_CV;
                        end else begin
                            cnt <= cnt + 4'd1;
                            comp_start <= 1'b1;
                            phase <= PHASE_CU;
                        end
                    end
                end
                PHASE_CV: begin
                    if (comp_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) cu_arr[2][bb] = comp_y[12*bb +: 12];
                        pk2_start <= 1'b1;
                        phase <= PHASE_CV2;
                    end
                end
                PHASE_CV2: begin
                    if (pk2_done) begin
                        for (bb = 0; bb < 128; bb = bb + 1) c_byte[960 + bb] = pk2_bytes[3071-8*bb -: 8];
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    assign shk_req[0] = h_req;
    assign shk_req[1] = g_req;
    assign shk_req[2] = sntt_req;
    assign shk_req[3] = cbd_req;
    assign shk_cfg = {cbd_cfg, sntt_cfg, {4'd1, 2'd3, 12'd64}, {4'd1, 2'd2, 12'd1184}};
    assign shk_blk_valid = h_bv | g_bv | sntt_bv | cbd_bv;
    assign shk_blk_data = ({1344{h_bv}} & h_bd)
                        | ({1344{g_bv}} & g_bd)
                        | ({1344{sntt_bv}} & sntt_bd)
                        | ({1344{cbd_bv}} & cbd_bd);
    assign shk_out_ready = h_or | g_or | sntt_or | cbd_or;

    genvar gc;
    generate
        for (gc = 0; gc < 1088; gc = gc + 1) begin: cout
            assign c_out[8703-8*gc -: 8] = c_byte[gc];
        end
    endgenerate
endmodule
