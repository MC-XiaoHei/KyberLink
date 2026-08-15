module kem_keygen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [255:0] d,
    input  wire [255:0] z,
    output reg         busy,
    output reg         done,
    output wire [9471:0]  ek_out,
    output wire [19199:0] dk_out,

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

    localparam PHASE_IDLE = 4'd0;
    localparam PHASE_G    = 4'd1;
    localparam PHASE_A    = 4'd2;
    localparam PHASE_S    = 4'd3;
    localparam PHASE_NTT  = 4'd4;
    localparam PHASE_MM   = 4'd5;
    localparam PHASE_PKTH = 4'd6;
    localparam PHASE_PKSH = 4'd7;
    localparam PHASE_H    = 4'd8;
    localparam PHASE_DONE = 4'd9;

    reg [3:0] phase;
    reg [3:0] cnt;

    reg [255:0] rho;
    reg [255:0] sigma;

    reg [11:0] a_arr [0:8][0:255];
    reg [11:0] s12   [0:5][0:255];
    reg [11:0] sh_arr[0:2][0:255];
    reg [11:0] eh_arr[0:2][0:255];
    reg [11:0] th_arr[0:2][0:255];

    reg [7:0] ek_byte [0:2047];
    reg [7:0] dk_byte [0:2399];
    reg [7:0] h_ek    [0:31];

    reg g_start;
    wire g_req, g_bv, g_or, g_osync;
    engine_client #(.NBLK_W(4)) u_gc (
        .clk(clk), .rst_n(rst_n),
        .start(g_start), .cfg({4'd1, 2'd3, 12'd33}), .nblk(4'd1),
        .msg_blk({768'b0, d, 8'h03, 312'b0}),
        .req_ready(shk_ready[0]), .blk_ready(shk_blk_ready),
        .out_valid(shk_out_valid), .done(shk_done[0]),
        .req_valid(g_req), .blk_valid(g_bv), .blk_data(g_bd), .out_ready(g_or), .blk_idx(),
        .out_sync(g_osync)
    );
    wire g_done = shk_done[0];
    wire [575:0] g_out = shk_out_data[575:0];
    wire [1343:0] g_bd;

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
        .rho(sigma),
        .i({5'd0, cnt[2:0]}),
        .busy(), .done(cbd_done),
        .coeffs(cbd_coeffs),
        .shk_req(cbd_req), .shk_cfg(cbd_cfg), .shk_ready(shk_ready[3]),
        .shk_done(shk_done[3]),
        .shk_blk_valid(cbd_bv), .shk_blk_ready(shk_blk_ready), .shk_blk_data(cbd_bd),
        .shk_out_valid(shk_out_valid), .shk_out_ready(cbd_or), .shk_out_data(shk_out_data)
    );

    wire [11:0] s12_tmp [0:255];
    genvar cg;
    generate
        for (cg = 0; cg < 256; cg = cg + 1) begin: cbdmap
            wire signed [2:0] sv = $signed(cbd_coeffs[3*cg +: 3]);
            wire signed [11:0] sex = {{9{sv[2]}}, sv};
            wire [12:0] sadd = sex + 13'd3329;
            assign s12_tmp[cg] = sv[2] ? sadd[11:0] : sex[11:0];
        end
    endgenerate

    wire ntt_done;
    wire [3071:0] ntt_out;
    reg ntt_start;

    wire [2:0] eh_idx3 = cnt[2:0] - 3'd3;
    wire [1:0] eh_idx = eh_idx3[1:0];

    wire [3071:0] ntt_in;
    genvar ng;
    generate
        for (ng = 0; ng < 256; ng = ng + 1) begin: nttin
            assign ntt_in[12*ng +: 12] = s12[cnt[2:0]][ng];
        end
    endgenerate

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
                assign mm_b[12*(256*ga+gb) +: 12] = sh_arr[ga][gb];
            end
        end
    endgenerate

    matmul u_mm (
        .clk(clk), .rst_n(rst_n),
        .start(mm_start), .mode(1'b0),
        .a_in(mm_a), .b_in(mm_b),
        .busy(), .done(mm_done),
        .c_out(mm_c)
    );

    wire pk_done;
    wire [3071:0] pk_bytes;
    reg pk_start;

    wire [3071:0] pk_coeffs;
    genvar pg;
    generate
        for (pg = 0; pg < 256; pg = pg + 1) begin: pkin
            assign pk_coeffs[12*pg +: 12] = (phase == PHASE_PKTH) ? th_arr[cnt[1:0]][pg] : sh_arr[cnt[1:0]][pg];
        end
    endgenerate

    pack u_pk (
        .clk(clk), .rst_n(rst_n),
        .start(pk_start), .mode(1'b0), .d(4'd12),
        .coeffs_in(pk_coeffs),
        .bytes_in(3072'b0),
        .busy(), .done(pk_done),
        .coeffs_out(), .bytes_out(pk_bytes)
    );

    wire h_done;
    wire [1087:0] h_out;
    reg h_start;

    wire [1087:0] h_msg;
    reg [7:0] h_msg_b [0:135];
    integer hc;
    integer hidx;
    always @(*) begin
        for (hc = 0; hc < 136; hc = hc + 1) begin
            hidx = {20'd0, {1'b0, h_base[10:0]} + {4'd0, hc[7:0]}};
            h_msg_b[hc] = (hidx < 12'd1184) ? ek_byte[hidx[10:0]] : 8'd0;
        end
    end
    genvar hj;
    wire [10:0] h_base = {3'b0, h_idx} * 11'd136;
    generate
        for (hj = 0; hj < 136; hj = hj + 1) begin: hmsg
            assign h_msg[8*hj +: 8] = h_msg_b[135-hj];
        end
    endgenerate

    wire h_req, h_bv, h_or, h_osync;
    wire [3:0] h_idx;
    wire [1343:0] h_bd;
    engine_client #(.NBLK_W(4)) u_hc (
        .clk(clk), .rst_n(rst_n),
        .start(h_start), .cfg({4'd1, 2'd2, 12'd1184}), .nblk(4'd9),
        .msg_blk({256'b0, h_msg}),
        .req_ready(shk_ready[1]), .blk_ready(shk_blk_ready),
        .out_valid(shk_out_valid), .done(shk_done[1]),
        .req_valid(h_req), .blk_valid(h_bv), .blk_data(h_bd), .out_ready(h_or), .blk_idx(h_idx),
        .out_sync(h_osync)
    );
    assign h_done = shk_done[1];
    assign h_out = shk_out_data[1087:0];

    integer bb;
    integer ths;
    integer thd;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            g_start <= 1'b0;
            sntt_start <= 1'b0;
            cbd_start <= 1'b0;
            ntt_start <= 1'b0;
            mm_start <= 1'b0;
            pk_start <= 1'b0;
            h_start <= 1'b0;
            cnt <= 4'd0;
        end else begin
            done <= 1'b0;
            g_start <= 1'b0;
            sntt_start <= 1'b0;
            cbd_start <= 1'b0;
            ntt_start <= 1'b0;
            mm_start <= 1'b0;
            pk_start <= 1'b0;
            h_start <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        g_start <= 1'b1;
                        phase <= PHASE_G;
                    end
                end
                PHASE_G: begin
                    if (g_osync) begin
                        rho <= g_out[575:320];
                        sigma <= g_out[319:64];
                    end
                    if (g_done) begin
                        cnt <= 4'd0;
                        sntt_start <= 1'b1;
                        phase <= PHASE_A;
                    end
                end
                PHASE_A: begin
                    if (sntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) a_arr[cnt][bb] = sntt_coeffs[12*bb +: 12];
                        if (cnt == 4'd8) begin
                            cnt <= 4'd0;
                            cbd_start <= 1'b1;
                            phase <= PHASE_S;
                        end else begin
                            cnt <= cnt + 4'd1;
                            sntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_S: begin
                    if (cbd_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) s12[cnt[2:0]][bb] = s12_tmp[bb];
                        if (cnt == 4'd5) begin
                            cnt <= 4'd0;
                            ntt_start <= 1'b1;
                            phase <= PHASE_NTT;
                        end else begin
                            cnt <= cnt + 4'd1;
                            cbd_start <= 1'b1;
                        end
                    end
                end
                PHASE_NTT: begin
                    if (ntt_done) begin
                        if (cnt < 4'd3) begin
                            for (bb = 0; bb < 256; bb = bb + 1) sh_arr[cnt[1:0]][bb] = ntt_out[12*bb +: 12];
                        end else begin
                            for (bb = 0; bb < 256; bb = bb + 1) eh_arr[eh_idx][bb] = ntt_out[12*bb +: 12];
                        end
                        if (cnt == 4'd5) begin
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
                        for (bb = 0; bb < 768; bb = bb + 1) begin
                            ths = ({19'd0, mm_c[12*bb +: 12]} + {19'd0, eh_arr[bb[9:8]][bb[7:0]]});
                            if (ths >= Q) begin
                                thd = ths - {20'd0, Q};
                                th_arr[bb[9:8]][bb[7:0]] = thd[11:0];
                            end else begin
                                th_arr[bb[9:8]][bb[7:0]] = ths[11:0];
                            end
                        end
                        cnt <= 4'd0;
                        pk_start <= 1'b1;
                        phase <= PHASE_PKTH;
                    end
                end
                PHASE_PKTH: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 384; bb = bb + 1) ek_byte[cnt*384 + bb] = pk_bytes[3071-8*bb -: 8];
                        if (cnt == 4'd2) begin
                            for (bb = 0; bb < 32; bb = bb + 1) ek_byte[1152 + bb] = rho[255-8*bb -: 8];
                            cnt <= 4'd0;
                            pk_start <= 1'b1;
                            phase <= PHASE_PKSH;
                        end else begin
                            cnt <= cnt + 4'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_PKSH: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 384; bb = bb + 1) dk_byte[cnt*384 + bb] = pk_bytes[3071-8*bb -: 8];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            h_start <= 1'b1;
                            phase <= PHASE_H;
                        end else begin
                            cnt <= cnt + 4'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_H: begin
                    if (h_osync) begin
                        for (bb = 0; bb < 32; bb = bb + 1) h_ek[bb] = h_out[1087-8*bb -: 8];
                    end
                    if (h_done) begin
                        phase <= PHASE_DONE;
                    end
                end
                PHASE_DONE: begin
                    for (bb = 0; bb < 1184; bb = bb + 1) dk_byte[1152 + bb] = ek_byte[bb];
                    for (bb = 0; bb < 32; bb = bb + 1) dk_byte[2336 + bb] = h_ek[bb];
                    for (bb = 0; bb < 32; bb = bb + 1) dk_byte[2368 + bb] = z[255-8*bb -: 8];
                    busy <= 1'b0;
                    done <= 1'b1;
                    phase <= PHASE_IDLE;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    assign shk_req[0] = g_req;
    assign shk_req[1] = h_req;
    assign shk_req[2] = sntt_req;
    assign shk_req[3] = cbd_req;
    assign shk_cfg = {cbd_cfg, sntt_cfg, {4'd1, 2'd2, 12'd1184}, {4'd1, 2'd3, 12'd33}};
    assign shk_blk_valid = g_bv | h_bv | sntt_bv | cbd_bv;
    assign shk_blk_data = ({1344{g_bv}} & g_bd)
                        | ({1344{h_bv}} & h_bd)
                        | ({1344{sntt_bv}} & sntt_bd)
                        | ({1344{cbd_bv}} & cbd_bd);
    assign shk_out_ready = g_or | h_or | sntt_or | cbd_or;

    genvar ge, gd;
    generate
        for (ge = 0; ge < 1184; ge = ge + 1) begin: eout
            assign ek_out[9471-8*ge -: 8] = ek_byte[ge];
        end
        for (gd = 0; gd < 2400; gd = gd + 1) begin: dout
            assign dk_out[19199-8*gd -: 8] = dk_byte[gd];
        end
    endgenerate
endmodule
