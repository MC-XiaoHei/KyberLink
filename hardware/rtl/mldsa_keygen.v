module mldsa_keygen (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] seed,
    output reg          busy,
    output reg          done,
    output wire [15615:0] vk_out,
    output wire [32255:0] sk_out
);
    localparam Q = 23'd8380417;

    localparam PHASE_IDLE   = 4'd0;
    localparam PHASE_G      = 4'd1;
    localparam PHASE_A      = 4'd2;
    localparam PHASE_S      = 4'd3;
    localparam PHASE_NTT_S  = 4'd4;
    localparam PHASE_MM     = 4'd5;
    localparam PHASE_INVTT  = 4'd6;
    localparam PHASE_TADJ   = 4'd7;
    localparam PHASE_P2R    = 4'd8;
    localparam PHASE_PACK_VK = 4'd9;
    localparam PHASE_PACK_S  = 4'd10;
    localparam PHASE_PACK_T0 = 4'd11;
    localparam PHASE_TR     = 4'd12;
    localparam PHASE_DONE   = 4'd13;

    reg [3:0] phase;
    reg [4:0] cnt;
    reg [10:0] cnt2;

    reg [255:0] rho;
    reg [511:0] rho2;
    reg [255:0] kk;

    reg [22:0] a_hat  [0:29][0:255];
    reg [22:0] s1_arr [0:4][0:255];
    reg [22:0] s2_arr [0:5][0:255];
    reg [22:0] s1_hat [0:4][0:255];
    reg [22:0] t_arr  [0:5][0:255];
    reg [22:0] tmp_arr[0:5][0:255];
    reg [22:0] t_std  [0:5][0:255];
    reg [9:0]  t1_arr [0:5][0:255];
    reg [22:0] t0_arr [0:5][0:255];

    reg [7:0] vk_byte [0:1951];
    reg [7:0] sk_byte [0:4031];
    reg [7:0] tr      [0:63];

    wire g_done;
    wire g_busy;
    wire [1087:0] g_out;
    reg g_start;

    shake #(.RATE_BYTES(136), .DOMAIN_BYTE(8'h1F)) u_g (
        .clk(clk), .rst_n(rst_n),
        .start(g_start), .len(12'd34),
        .msg({seed, 8'd6, 8'd5, 816'b0}),
        .out_blocks(4'd1),
        .msg_valid(1'b0), .need_msg(),
        .busy(g_busy), .done(g_done),
        .out(g_out)
    );

    wire rntt_done;
    wire [5887:0] rntt_coeffs;
    reg rntt_start;

    wire [4:0] a_row_w = cnt / 5'd5;
    wire [4:0] a_col_w = cnt % 5'd5;
    wire [2:0] a_row = a_row_w[2:0];
    wire [2:0] a_col = a_col_w[2:0];

    rej_ntt u_rntt (
        .clk(clk), .rst_n(rst_n),
        .start(rntt_start),
        .rho(rho),
        .s({5'd0, a_col}), .r({5'd0, a_row}),
        .busy(), .done(rntt_done),
        .coeffs(rntt_coeffs)
    );

    wire rb_done;
    wire [5887:0] rb_coeffs;
    reg rb_start;

    rej_bounded u_rb (
        .clk(clk), .rst_n(rst_n),
        .start(rb_start),
        .rho(rho2),
        .idx_in({11'd0, cnt}),
        .busy(), .done(rb_done),
        .coeffs(rb_coeffs)
    );

    wire nttd_done;
    wire [5887:0] nttd_out;
    reg nttd_start;

    wire [5887:0] nttd_in;
    genvar ng;
    generate
        for (ng = 0; ng < 256; ng = ng + 1) begin: nttdin
            assign nttd_in[23*ng +: 23] = s1_arr[cnt[2:0]][ng];
        end
    endgenerate

    ntt_dsa u_nttd (
        .clk(clk), .rst_n(rst_n),
        .start(nttd_start),
        .coeffs_in(nttd_in),
        .busy(), .done(nttd_done),
        .coeffs_out(nttd_out)
    );

    wire mm_done;
    wire [35327:0] mm_c;
    reg mm_start;

    wire [176639:0] mm_a;
    wire [29439:0]  mm_b;
    genvar ga, gb;
    generate
        for (ga = 0; ga < 30; ga = ga + 1) begin: amap
            for (gb = 0; gb < 256; gb = gb + 1) begin: amapk
                assign mm_a[23*(256*ga+gb) +: 23] = a_hat[ga][gb];
            end
        end
        for (ga = 0; ga < 5; ga = ga + 1) begin: bmap
            for (gb = 0; gb < 256; gb = gb + 1) begin: bmapk
                assign mm_b[23*(256*ga+gb) +: 23] = s1_hat[ga][gb];
            end
        end
    endgenerate

    matmul_dsa u_mm (
        .clk(clk), .rst_n(rst_n),
        .start(mm_start),
        .a_in(mm_a), .b_in(mm_b),
        .busy(), .done(mm_done),
        .c_out(mm_c)
    );

    wire invd_done;
    wire [5887:0] invd_out;
    reg invd_start;

    wire [5887:0] invd_in;
    generate
        for (ng = 0; ng < 256; ng = ng + 1) begin: invdin
            assign invd_in[23*ng +: 23] = t_arr[cnt[2:0]][ng];
        end
    endgenerate

    invntt_dsa u_invd (
        .clk(clk), .rst_n(rst_n),
        .start(invd_start),
        .coeffs_in(invd_in),
        .busy(), .done(invd_done),
        .coeffs_out(invd_out)
    );

    wire pk_done;
    wire [5119:0] pk_bytes;
    reg pk_start;

    wire [22:0] pksrc [0:255];
    genvar gp;
    generate
        for (gp = 0; gp < 256; gp = gp + 1) begin: pkm
            wire [22:0] xv = (phase == PHASE_PACK_VK) ? {13'd0, t1_arr[cnt[2:0]][gp]} :
                             (phase == PHASE_PACK_S) ? ((cnt < 5'd5) ? s1_arr[cnt[2:0]][gp] : s2_arr[s2i][gp]) :
                             t0_arr[cnt[2:0]][gp];
            wire [23:0] bpx = (phase == PHASE_PACK_S) ? 24'd4 :
                             (phase == PHASE_PACK_T0) ? 24'd4096 : 24'd0;
            wire [23:0] flat = (phase == PHASE_PACK_VK) ? {1'b0, xv} :
                               (({1'b0, xv} <= bpx) ? (bpx - {1'b0, xv}) : (bpx + {1'b0, Q} - {1'b0, xv}));
            assign pksrc[gp] = flat[22:0];
        end
    endgenerate

    wire [5887:0] pk_coeffs;
    genvar pj;
    generate
        for (pj = 0; pj < 256; pj = pj + 1) begin: pkin
            assign pk_coeffs[23*pj +: 23] = pksrc[pj];
        end
    endgenerate

    pack_dsa u_pkdsa (
        .clk(clk), .rst_n(rst_n),
        .start(pk_start),
        .mode(1'b0),
        .d((phase == PHASE_PACK_S) ? 5'd4 : (phase == PHASE_PACK_T0) ? 5'd13 : 5'd10),
        .coeffs_in(pk_coeffs),
        .bytes_in(5120'b0),
        .busy(), .done(pk_done),
        .coeffs_out(), .bytes_out(pk_bytes)
    );

    wire tr_done;
    wire tr_busy;
    wire [1087:0] tr_out;
    reg tr_start;
    reg [3:0] tr_blk;
    reg tr_valid;
    reg tr_need_d1;
    wire tr_need;

    wire [1087:0] tr_msg;
    reg [7:0] tr_msg_b [0:135];
    integer tc;
    integer tidx;
    always @(*) begin
        for (tc = 0; tc < 136; tc = tc + 1) begin
            tidx = {20'd0, {1'b0, tr_base[10:0]} + {4'd0, tc[7:0]}};
            tr_msg_b[tc] = (tidx < 12'd1952) ? vk_byte[tidx[10:0]] : 8'd0;
        end
    end
    wire [10:0] tr_base = {3'b0, tr_blk} * 11'd136;
    genvar tj;
    generate
        for (tj = 0; tj < 136; tj = tj + 1) begin: trmsg
            assign tr_msg[8*tj +: 8] = tr_msg_b[135-tj];
        end
    endgenerate

    shake #(.RATE_BYTES(136), .DOMAIN_BYTE(8'h1F)) u_tr (
        .clk(clk), .rst_n(rst_n),
        .start(tr_start), .len(12'd1952),
        .msg(tr_msg), .out_blocks(4'd1),
        .msg_valid(tr_valid), .need_msg(tr_need),
        .busy(tr_busy), .done(tr_done),
        .out(tr_out)
    );

    wire [10:0] p2r_r1 = (x13[12:0] > 13'd4096) ? ({1'b0, x13[22:13]} + 10'd1) : {1'b0, x13[22:13]};
    wire [22:0] p2r_r0 = (x13[12:0] > 13'd4096) ? ({10'd0, x13[12:0]} + Q - 23'd8192) : {10'd0, x13[12:0]};
    wire [22:0] x13 = t_std[cnt2[10:8]][cnt2[7:0]];

    wire [4:0] s2sub_w = cnt - 5'd5;
    wire [2:0] s2i = s2sub_w[2:0];

    integer bb;
    reg [23:0] ts;
    reg [23:0] td;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            g_start <= 1'b0;
            rntt_start <= 1'b0;
            rb_start <= 1'b0;
            nttd_start <= 1'b0;
            mm_start <= 1'b0;
            invd_start <= 1'b0;
            pk_start <= 1'b0;
            tr_start <= 1'b0;
            tr_valid <= 1'b0;
            tr_need_d1 <= 1'b0;
            tr_blk <= 4'd0;
            cnt <= 5'd0;
            cnt2 <= 11'd0;
        end else begin
            done <= 1'b0;
            g_start <= 1'b0;
            rntt_start <= 1'b0;
            rb_start <= 1'b0;
            nttd_start <= 1'b0;
            mm_start <= 1'b0;
            invd_start <= 1'b0;
            pk_start <= 1'b0;
            tr_start <= 1'b0;
            tr_valid <= 1'b0;
            tr_need_d1 <= tr_need;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        g_start <= 1'b1;
                        phase <= PHASE_G;
                    end
                end
                PHASE_G: begin
                    if (g_done) begin
                        rho <= g_out[1087:832];
                        rho2 <= g_out[831:320];
                        kk <= g_out[319:64];
                        for (bb = 0; bb < 32; bb = bb + 1) begin
                            vk_byte[bb] = g_out[1087 - 8*bb -: 8];
                            sk_byte[bb] = g_out[1087 - 8*bb -: 8];
                            sk_byte[32 + bb] = g_out[319 - 8*bb -: 8];
                        end
                        cnt <= 5'd0;
                        rntt_start <= 1'b1;
                        phase <= PHASE_A;
                    end
                end
                PHASE_A: begin
                    if (rntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) a_hat[cnt[4:0]][bb] = rntt_coeffs[23*bb +: 23];
                        if (cnt == 5'd29) begin
                            cnt <= 5'd0;
                            rb_start <= 1'b1;
                            phase <= PHASE_S;
                        end else begin
                            cnt <= cnt + 5'd1;
                            rntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_S: begin
                    if (rb_done) begin
                        if (cnt < 5'd5) begin
                            for (bb = 0; bb < 256; bb = bb + 1) s1_arr[cnt[2:0]][bb] = rb_coeffs[23*bb +: 23];
                        end else begin
                            for (bb = 0; bb < 256; bb = bb + 1) s2_arr[s2i][bb] = rb_coeffs[23*bb +: 23];
                        end
                        if (cnt == 5'd10) begin
                            cnt <= 5'd0;
                            nttd_start <= 1'b1;
                            phase <= PHASE_NTT_S;
                        end else begin
                            cnt <= cnt + 5'd1;
                            rb_start <= 1'b1;
                        end
                    end
                end
                PHASE_NTT_S: begin
                    if (nttd_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) s1_hat[cnt[2:0]][bb] = nttd_out[23*bb +: 23];
                        if (cnt == 5'd4) begin
                            cnt <= 5'd0;
                            mm_start <= 1'b1;
                            phase <= PHASE_MM;
                        end else begin
                            cnt <= cnt + 5'd1;
                            nttd_start <= 1'b1;
                        end
                    end
                end
                PHASE_MM: begin
                    if (mm_done) begin
                        for (bb = 0; bb < 1536; bb = bb + 1) t_arr[bb[10:8]][bb[7:0]] = mm_c[23*bb +: 23];
                        cnt <= 5'd0;
                        invd_start <= 1'b1;
                        phase <= PHASE_INVTT;
                    end
                end
                PHASE_INVTT: begin
                    if (invd_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) tmp_arr[cnt[2:0]][bb] = invd_out[23*bb +: 23];
                        if (cnt == 5'd5) begin
                            cnt2 <= 11'd0;
                            phase <= PHASE_TADJ;
                        end else begin
                            cnt <= cnt + 5'd1;
                            invd_start <= 1'b1;
                        end
                    end
                end
                PHASE_TADJ: begin
                    ts = ({1'b0, tmp_arr[cnt2[10:8]][cnt2[7:0]]} + {1'b0, s2_arr[cnt2[10:8]][cnt2[7:0]]});
                    if (ts >= {1'b0, Q}) begin
                        td = ts - {1'b0, Q};
                        t_std[cnt2[10:8]][cnt2[7:0]] = td[22:0];
                    end else begin
                        t_std[cnt2[10:8]][cnt2[7:0]] = ts[22:0];
                    end
                    if (cnt2 == 11'd1535) begin
                        cnt2 <= 11'd0;
                        phase <= PHASE_P2R;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_P2R: begin
                    t1_arr[cnt2[10:8]][cnt2[7:0]] = p2r_r1[9:0];
                    t0_arr[cnt2[10:8]][cnt2[7:0]] = p2r_r0;
                    if (cnt2 == 11'd1535) begin
                        cnt <= 5'd0;
                        pk_start <= 1'b1;
                        phase <= PHASE_PACK_VK;
                    end else begin
                        cnt2 <= cnt2 + 11'd1;
                    end
                end
                PHASE_PACK_VK: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 320; bb = bb + 1) vk_byte[32 + cnt[2:0]*320 + bb] = pk_bytes[5119-8*bb -: 8];
                        if (cnt == 5'd5) begin
                            cnt <= 5'd0;
                            pk_start <= 1'b1;
                            phase <= PHASE_PACK_S;
                        end else begin
                            cnt <= cnt + 5'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_PACK_S: begin
                    if (pk_done) begin
                        if (cnt < 5'd5) begin
                            for (bb = 0; bb < 128; bb = bb + 1) sk_byte[128 + cnt[2:0]*128 + bb] = pk_bytes[5119-8*bb -: 8];
                        end else begin
                            for (bb = 0; bb < 128; bb = bb + 1) sk_byte[768 + {2'd0, s2i} * 8'd128 + bb] = pk_bytes[5119-8*bb -: 8];
                        end
                        if (cnt == 5'd10) begin
                            cnt <= 5'd0;
                            pk_start <= 1'b1;
                            phase <= PHASE_PACK_T0;
                        end else begin
                            cnt <= cnt + 5'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_PACK_T0: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 416; bb = bb + 1) sk_byte[1536 + cnt[2:0]*416 + bb] = pk_bytes[5119-8*bb -: 8];
                        if (cnt == 5'd5) begin
                            cnt <= 5'd0;
                            tr_blk <= 4'd0;
                            tr_start <= 1'b1;
                            phase <= PHASE_TR;
                        end else begin
                            cnt <= cnt + 5'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_TR: begin
                    if (tr_need && !tr_need_d1) begin
                        tr_valid <= 1'b1;
                        tr_blk <= tr_blk + 4'd1;
                    end
                    if (tr_done) begin
                        for (bb = 0; bb < 64; bb = bb + 1) tr[bb] = tr_out[1087 - 8*bb -: 8];
                        phase <= PHASE_DONE;
                    end
                end
                PHASE_DONE: begin
                    for (bb = 0; bb < 64; bb = bb + 1) sk_byte[64 + bb] = tr[bb];
                    busy <= 1'b0;
                    done <= 1'b1;
                    phase <= PHASE_IDLE;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    genvar gv, gs;
    generate
        for (gv = 0; gv < 1952; gv = gv + 1) begin: vout
            assign vk_out[15615-8*gv -: 8] = vk_byte[gv];
        end
        for (gs = 0; gs < 4032; gs = gs + 1) begin: sout
            assign sk_out[32255-8*gs -: 8] = sk_byte[gs];
        end
    endgenerate
endmodule
