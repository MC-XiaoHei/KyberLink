module kem_decap (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [19199:0] dk_in,
    input  wire [8703:0]  c_in,
    output reg          busy,
    output reg          done,
    output reg  [255:0]  k_out,

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
    localparam Q = 12'd3329;

    localparam PHASE_IDLE  = 6'd0;
    localparam PHASE_DECU  = 6'd1;
    localparam PHASE_DECU2 = 6'd2;
    localparam PHASE_DECV  = 6'd3;
    localparam PHASE_DECV2 = 6'd4;
    localparam PHASE_DECSH = 6'd5;
    localparam PHASE_NTT   = 6'd6;
    localparam PHASE_DOT   = 6'd7;
    localparam PHASE_INV   = 6'd8;
    localparam PHASE_WADJ  = 6'd9;
    localparam PHASE_MENC  = 6'd10;
    localparam PHASE_MENC2 = 6'd11;
    localparam PHASE_G     = 6'd12;
    localparam PHASE_JBAR  = 6'd13;
    localparam PHASE_CTH   = 6'd14;
    localparam PHASE_CA    = 6'd15;
    localparam PHASE_CY    = 6'd16;
    localparam PHASE_CYH   = 6'd17;
    localparam PHASE_CMM   = 6'd18;
    localparam PHASE_CUINV = 6'd19;
    localparam PHASE_CMU   = 6'd20;
    localparam PHASE_CVD   = 6'd21;
    localparam PHASE_CVINV = 6'd22;
    localparam PHASE_CVA   = 6'd23;
    localparam PHASE_CENC  = 6'd24;
    localparam PHASE_CENC2 = 6'd25;
    localparam PHASE_CVENC = 6'd26;
    localparam PHASE_CVENC2= 6'd27;
    localparam PHASE_CMP   = 6'd28;
    localparam PHASE_DONE  = 6'd29;

    reg [5:0] phase;
    reg [3:0] cnt;

    reg [7:0] dk_byte [0:2399];
    reg [7:0] c_byte  [0:1087];
    reg [7:0] cp_byte [0:1087];
    reg [7:0] m_byte  [0:31];
    reg [7:0] kbar_byte [0:31];

    reg [11:0] u_arr [0:767];
    reg [11:0] v_arr [0:255];
    reg [11:0] sh_arr[0:767];
    reg [11:0] uh_arr[0:767];
    reg [11:0] w_arr [0:255];
    reg [11:0] mu_arr[0:255];
    reg [11:0] th_arr[0:767];
    reg [11:0] a_arr [0:8][0:255];
    reg [11:0] y_arr [0:2][0:255];
    reg [11:0] e1_arr[0:2][0:255];
    reg [11:0] e2_arr[0:255];
    reg [11:0] yh_arr[0:2][0:255];
    reg [11:0] cpr_arr[0:767];
    reg [11:0] cpv_arr[0:255];
    reg [11:0] cpmu_arr[0:255];

    reg [255:0] kp_reg;
    reg [255:0] rp_reg;

    wire [255:0] rho = {dk_byte[2304], dk_byte[2305], dk_byte[2306], dk_byte[2307],
        dk_byte[2308], dk_byte[2309], dk_byte[2310], dk_byte[2311],
        dk_byte[2312], dk_byte[2313], dk_byte[2314], dk_byte[2315],
        dk_byte[2316], dk_byte[2317], dk_byte[2318], dk_byte[2319],
        dk_byte[2320], dk_byte[2321], dk_byte[2322], dk_byte[2323],
        dk_byte[2324], dk_byte[2325], dk_byte[2326], dk_byte[2327],
        dk_byte[2328], dk_byte[2329], dk_byte[2330], dk_byte[2331],
        dk_byte[2332], dk_byte[2333], dk_byte[2334], dk_byte[2335]};

    wire pk_done;
    wire [3071:0] pk_bytes;
    wire [3071:0] pk_coeffs;
    reg pk_start;
    reg pk_mode;
    reg [3:0] pk_d;

    wire [3071:0] pk_bytes_in;
    reg [7:0] pk_src [0:383];
    integer pkb;
    integer pkk;
    always @(*) begin
        for (pkb = 0; pkb < 384; pkb = pkb + 1) begin
            pkk = 383 - pkb;
            case (phase)
                PHASE_DECU: pk_src[pkb] = (pkk < 320) ? c_byte[320*cnt[1:0] + pkk] : 8'd0;
                PHASE_DECV: pk_src[pkb] = (pkk < 128) ? c_byte[960 + pkk] : 8'd0;
                PHASE_DECSH: pk_src[pkb] = dk_byte[384*cnt[1:0] + pkk];
                default: pk_src[pkb] = dk_byte[1152 + 384*cnt[1:0] + pkk];
            endcase
        end
    end
    genvar pkj;
    generate
        for (pkj = 0; pkj < 384; pkj = pkj + 1) begin: pkjmap
            assign pk_bytes_in[8*pkj +: 8] = pk_src[pkj];
        end
    endgenerate

    pack u_pk (
        .clk(clk), .rst_n(rst_n),
        .start(pk_start), .mode(pk_mode), .d(pk_d),
        .coeffs_in(comp_y),
        .bytes_in(pk_bytes_in),
        .busy(), .done(pk_done),
        .coeffs_out(pk_coeffs), .bytes_out(pk_bytes)
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
            assign comp_x[12*cq +: 12] =
                (phase == PHASE_MENC) ? w_arr[cq] :
                (phase == PHASE_CMU) ? {11'd0, m_byte[cq/8][cq%8]} :
                (phase == PHASE_CENC) ? cpr_arr[256*cnt[1:0] + cq] :
                (phase == PHASE_CVENC) ? cpv_arr[cq] :
                                         pk_coeffs[12*cq +: 12];
        end
    endgenerate

    compress u_comp (
        .clk(clk), .rst_n(rst_n),
        .start(comp_start), .mode(comp_mode), .d(comp_d),
        .x_in(comp_x),
        .busy(), .done(comp_done),
        .y_out(comp_y)
    );

    wire ntt_done;
    wire [3071:0] ntt_out;
    reg ntt_start;

    wire [3071:0] ntt_in;
    genvar ng;
    generate
        for (ng = 0; ng < 256; ng = ng + 1) begin: nttin
            assign ntt_in[12*ng +: 12] =
                (phase == PHASE_NTT) ? u_arr[256*cnt[1:0] + ng] :
                (phase == PHASE_CYH) ? y_arr[cnt[1:0]][ng] :
                                       cpr_arr[256*cnt[1:0] + ng];
        end
    endgenerate

    ntt u_ntt (
        .clk(clk), .rst_n(rst_n),
        .start(ntt_start),
        .coeffs_in(ntt_in),
        .busy(), .done(ntt_done),
        .coeffs_out(ntt_out)
    );

    wire inv_done;
    wire [3071:0] inv_out;
    reg inv_start;

    wire [3071:0] inv_in;
    genvar ig;
    generate
        for (ig = 0; ig < 256; ig = ig + 1) begin: invin
            assign inv_in[12*ig +: 12] =
                (phase == PHASE_INV) ? w_arr[ig] :
                (phase == PHASE_CVINV) ? cpv_arr[ig] :
                                         cpr_arr[256*cnt[1:0] + ig];
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
        for (da = 0; da < 3; da = da + 1) begin: dmap
            for (db = 0; db < 256; db = db + 1) begin: dmapk
                assign dm_a[12*(256*da+db) +: 12] = (phase == PHASE_DOT) ? sh_arr[256*da+db] : th_arr[256*da+db];
                assign dm_b[12*(256*da+db) +: 12] = (phase == PHASE_DOT) ? uh_arr[256*da+db] : yh_arr[da][db];
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

    wire sntt_done;
    wire [3071:0] sntt_coeffs;
    reg sntt_start;
    wire sntt_req;
    wire [17:0] sntt_cfg;
    wire sntt_bv;
    wire [1343:0] sntt_bd;
    wire sntt_or;
    assign sntt_cfg = {4'd5, 2'd0, 12'd34};

    wire cbd_req;
    wire [17:0] cbd_cfg;
    wire cbd_bv;
    wire [1343:0] cbd_bd;
    wire cbd_or;
    assign cbd_cfg = {4'd1, 2'd1, 12'd33};

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
        .coeffs(sntt_coeffs),
        .shk_req(sntt_req), .shk_cfg(sntt_cfg),
        .shk_ready(shk_ready[2]), .shk_done(shk_done[2]),
        .shk_blk_valid(sntt_bv), .shk_blk_ready(shk_blk_ready), .shk_blk_data(sntt_bd),
        .shk_out_valid(shk_out_valid), .shk_out_ready(sntt_or), .shk_out_data(shk_out_data),
        .error()
    );

    wire cbd_done;
    wire [767:0] cbd_coeffs;
    reg cbd_start;

    sample_cbd u_scbd (
        .clk(clk), .rst_n(rst_n),
        .start(cbd_start),
        .rho(rp_reg),
        .i({5'd0, cnt[2:0]}),
        .busy(), .done(cbd_done),
        .coeffs(cbd_coeffs),
        .shk_req(cbd_req), .shk_cfg(cbd_cfg),
        .shk_ready(shk_ready[3]), .shk_done(shk_done[3]),
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

    wire [2:0] e1_idx3 = cnt[2:0] - 3'd3;
    wire [1:0] e1_idx = e1_idx3[1:0];

    wire g_done;
    wire g_osync;
    wire [575:0] g_out;
    wire [3:0] g_idx;
    reg g_start;
    wire g_req;
    wire g_bv;
    wire [1343:0] g_bd;
    wire g_or;

    engine_client #(.NBLK_W(4)) g_cli (
        .clk(clk), .rst_n(rst_n),
        .start(g_start), .cfg({4'd1, 2'd3, 12'd64}), .nblk(4'd1),
        .msg_blk({768'b0, m_byte[0], m_byte[1], m_byte[2], m_byte[3], m_byte[4], m_byte[5], m_byte[6], m_byte[7],
              m_byte[8], m_byte[9], m_byte[10], m_byte[11], m_byte[12], m_byte[13], m_byte[14], m_byte[15],
              m_byte[16], m_byte[17], m_byte[18], m_byte[19], m_byte[20], m_byte[21], m_byte[22], m_byte[23],
              m_byte[24], m_byte[25], m_byte[26], m_byte[27], m_byte[28], m_byte[29], m_byte[30], m_byte[31],
              dk_byte[2336], dk_byte[2337], dk_byte[2338], dk_byte[2339], dk_byte[2340], dk_byte[2341], dk_byte[2342], dk_byte[2343],
              dk_byte[2344], dk_byte[2345], dk_byte[2346], dk_byte[2347], dk_byte[2348], dk_byte[2349], dk_byte[2350], dk_byte[2351],
              dk_byte[2352], dk_byte[2353], dk_byte[2354], dk_byte[2355], dk_byte[2356], dk_byte[2357], dk_byte[2358], dk_byte[2359],
              dk_byte[2360], dk_byte[2361], dk_byte[2362], dk_byte[2363], dk_byte[2364], dk_byte[2365], dk_byte[2366], dk_byte[2367],
              64'b0}),
        .req_ready(shk_ready[0]), .blk_ready(shk_blk_ready), .out_valid(shk_out_valid), .done(shk_done[0]),
        .req_valid(g_req), .blk_valid(g_bv), .blk_data(g_bd), .out_ready(g_or), .blk_idx(g_idx), .out_sync(g_osync)
    );
    assign g_done = shk_done[0];
    assign g_out = shk_out_data[575:0];

    wire j_done;
    wire j_osync;
    wire [1087:0] j_out;
    wire [3:0] j_idx;
    reg j_start;
    wire j_req;
    wire j_bv;
    wire [1343:0] j_bd;
    wire j_or;

    wire [1087:0] j_msg;
    reg [7:0] j_msg_b [0:135];
    integer jc;
    integer jidx;
    wire [10:0] j_base = {3'b0, j_idx} * 11'd136;
    always @(*) begin
        for (jc = 0; jc < 136; jc = jc + 1) begin
            jidx = {20'd0, {1'b0, j_base[10:0]} + {4'd0, jc[7:0]}};
            if (jidx < 12'd32) begin
                j_msg_b[jc] = dk_byte[12'd2368 + {7'd0, jidx[4:0]}];
            end else if (jidx < 12'd1120) begin
                j_msg_b[jc] = c_byte[jidx[10:0] - 11'd32];
            end else begin
                j_msg_b[jc] = 8'd0;
            end
        end
    end
    genvar jj;
    generate
        for (jj = 0; jj < 136; jj = jj + 1) begin: jmsg
            assign j_msg[8*jj +: 8] = j_msg_b[135-jj];
        end
    endgenerate

    engine_client #(.NBLK_W(4)) j_cli (
        .clk(clk), .rst_n(rst_n),
        .start(j_start), .cfg({4'd1, 2'd1, 12'd1120}), .nblk(4'd9),
        .msg_blk({256'b0, j_msg}),
        .req_ready(shk_ready[1]), .blk_ready(shk_blk_ready), .out_valid(shk_out_valid), .done(shk_done[1]),
        .req_valid(j_req), .blk_valid(j_bv), .blk_data(j_bd), .out_ready(j_or), .blk_idx(j_idx), .out_sync(j_osync)
    );
    assign j_done = shk_done[1];
    assign j_out = shk_out_data[1087:0];

    integer bb;
    integer ts;
    integer td;
    reg cmp_eq;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            k_out <= 256'd0;
            pk_start <= 1'b0;
            pk_mode <= 1'b0;
            pk_d <= 4'd0;
            comp_start <= 1'b0;
            comp_mode <= 1'b0;
            comp_d <= 4'd0;
            ntt_start <= 1'b0;
            inv_start <= 1'b0;
            dm_start <= 1'b0;
            mm_start <= 1'b0;
            sntt_start <= 1'b0;
            cbd_start <= 1'b0;
            g_start <= 1'b0;
            j_start <= 1'b0;
            kp_reg <= 256'd0;
            rp_reg <= 256'd0;
            cnt <= 4'd0;
        end else begin
            done <= 1'b0;
            pk_start <= 1'b0;
            comp_start <= 1'b0;
            ntt_start <= 1'b0;
            inv_start <= 1'b0;
            dm_start <= 1'b0;
            mm_start <= 1'b0;
            sntt_start <= 1'b0;
            cbd_start <= 1'b0;
            g_start <= 1'b0;
            j_start <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        for (bb = 0; bb < 2400; bb = bb + 1) dk_byte[bb] = dk_in[19199-8*bb -: 8];
                        for (bb = 0; bb < 1088; bb = bb + 1) c_byte[bb] = c_in[8703-8*bb -: 8];
                        cnt <= 4'd0;
                        pk_mode <= 1'b1;
                        pk_d <= 4'd10;
                        pk_start <= 1'b1;
                        phase <= PHASE_DECU;
                    end
                end
                PHASE_DECU: begin
                    if (pk_done) begin
                        comp_mode <= 1'b1;
                        comp_d <= 4'd10;
                        comp_start <= 1'b1;
                        phase <= PHASE_DECU2;
                    end
                end
                PHASE_DECU2: begin
                    if (comp_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) u_arr[256*cnt[1:0] + bb] = comp_y[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            pk_mode <= 1'b1;
                            pk_d <= 4'd4;
                            pk_start <= 1'b1;
                            phase <= PHASE_DECV;
                        end else begin
                            cnt <= cnt + 4'd1;
                            pk_start <= 1'b1;
                            phase <= PHASE_DECU;
                        end
                    end
                end
                PHASE_DECV: begin
                    if (pk_done) begin
                        comp_mode <= 1'b1;
                        comp_d <= 4'd4;
                        comp_start <= 1'b1;
                        phase <= PHASE_DECV2;
                    end
                end
                PHASE_DECV2: begin
                    if (comp_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) v_arr[bb] = comp_y[12*bb +: 12];
                        cnt <= 4'd0;
                        pk_mode <= 1'b1;
                        pk_d <= 4'd12;
                        pk_start <= 1'b1;
                        phase <= PHASE_DECSH;
                    end
                end
                PHASE_DECSH: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) sh_arr[256*cnt[1:0] + bb] = pk_coeffs[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            ntt_start <= 1'b1;
                            phase <= PHASE_NTT;
                        end else begin
                            cnt <= cnt + 4'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_NTT: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) uh_arr[256*cnt[1:0] + bb] = ntt_out[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            dm_start <= 1'b1;
                            phase <= PHASE_DOT;
                        end else begin
                            cnt <= cnt + 4'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_DOT: begin
                    if (dm_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) w_arr[bb] = dm_c[12*bb +: 12];
                        inv_start <= 1'b1;
                        phase <= PHASE_INV;
                    end
                end
                PHASE_INV: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) w_arr[bb] = inv_out[12*bb +: 12];
                        phase <= PHASE_WADJ;
                    end
                end
                PHASE_WADJ: begin
                    for (bb = 0; bb < 256; bb = bb + 1) begin
                        ts = ({20'd0, v_arr[bb]} + {20'd0, Q}) - {20'd0, w_arr[bb]};
                        if (ts >= Q) td = ts - {20'd0, Q};
                        else td = ts;
                        w_arr[bb] = td[11:0];
                    end
                    cnt <= 4'd0;
                    comp_mode <= 1'b0;
                    comp_d <= 4'd1;
                    comp_start <= 1'b1;
                    phase <= PHASE_MENC;
                end
                PHASE_MENC: begin
                    if (comp_done) begin
                        pk_mode <= 1'b0;
                        pk_d <= 4'd1;
                        pk_start <= 1'b1;
                        phase <= PHASE_MENC2;
                    end
                end
                PHASE_MENC2: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 32; bb = bb + 1) m_byte[bb] = pk_bytes[3071-8*bb -: 8];
                        cnt <= 4'd0;
                        g_start <= 1'b1;
                        phase <= PHASE_G;
                    end
                end
                PHASE_G: begin
                    if (g_osync) begin
                        kp_reg <= g_out[575:320];
                        rp_reg <= g_out[319:64];
                    end
                    if (g_done) begin
                        j_start <= 1'b1;
                        phase <= PHASE_JBAR;
                    end
                end
                PHASE_JBAR: begin
                    if (j_osync) begin
                        for (bb = 0; bb < 32; bb = bb + 1) kbar_byte[bb] = j_out[1087-8*bb -: 8];
                    end
                    if (j_done) begin
                        cnt <= 4'd0;
                        pk_mode <= 1'b1;
                        pk_d <= 4'd12;
                        pk_start <= 1'b1;
                        phase <= PHASE_CTH;
                    end
                end
                PHASE_CTH: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) th_arr[256*cnt[1:0] + bb] = pk_coeffs[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            sntt_start <= 1'b1;
                            phase <= PHASE_CA;
                        end else begin
                            cnt <= cnt + 4'd1;
                            pk_start <= 1'b1;
                        end
                    end
                end
                PHASE_CA: begin
                    if (sntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) a_arr[cnt][bb] = sntt_coeffs[12*bb +: 12];
                        if (cnt == 4'd8) begin
                            cnt <= 4'd0;
                            cbd_start <= 1'b1;
                            phase <= PHASE_CY;
                        end else begin
                            cnt <= cnt + 4'd1;
                            sntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_CY: begin
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
                            phase <= PHASE_CYH;
                        end else begin
                            cnt <= cnt + 4'd1;
                            cbd_start <= 1'b1;
                        end
                    end
                end
                PHASE_CYH: begin
                    if (ntt_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) yh_arr[cnt[1:0]][bb] = ntt_out[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            mm_start <= 1'b1;
                            phase <= PHASE_CMM;
                        end else begin
                            cnt <= cnt + 4'd1;
                            ntt_start <= 1'b1;
                        end
                    end
                end
                PHASE_CMM: begin
                    if (mm_done) begin
                        for (bb = 0; bb < 768; bb = bb + 1) cpr_arr[bb] = mm_c[12*bb +: 12];
                        cnt <= 4'd0;
                        inv_start <= 1'b1;
                        phase <= PHASE_CUINV;
                    end
                end
                PHASE_CUINV: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) cpr_arr[256*cnt[1:0] + bb] = inv_out[12*bb +: 12];
                        if (cnt == 4'd2) begin
                            for (bb = 0; bb < 768; bb = bb + 1) begin
                                ts = ({19'd0, cpr_arr[bb]} + {19'd0, e1_arr[bb[9:8]][bb[7:0]]});
                                if (ts >= Q) begin
                                    td = ts - {20'd0, Q};
                                    cpr_arr[bb] = td[11:0];
                                end else begin
                                    cpr_arr[bb] = ts[11:0];
                                end
                            end
                            cnt <= 4'd0;
                            comp_mode <= 1'b1;
                            comp_d <= 4'd1;
                            comp_start <= 1'b1;
                            phase <= PHASE_CMU;
                        end else begin
                            cnt <= cnt + 4'd1;
                            inv_start <= 1'b1;
                        end
                    end
                end
                PHASE_CMU: begin
                    if (comp_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) cpmu_arr[bb] = comp_y[12*bb +: 12];
                        cnt <= 4'd0;
                        dm_start <= 1'b1;
                        phase <= PHASE_CVD;
                    end
                end
                PHASE_CVD: begin
                    if (dm_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) cpv_arr[bb] = dm_c[12*bb +: 12];
                        inv_start <= 1'b1;
                        phase <= PHASE_CVINV;
                    end
                end
                PHASE_CVINV: begin
                    if (inv_done) begin
                        for (bb = 0; bb < 256; bb = bb + 1) cpv_arr[bb] = inv_out[12*bb +: 12];
                        phase <= PHASE_CVA;
                    end
                end
                PHASE_CVA: begin
                    for (bb = 0; bb < 256; bb = bb + 1) begin
                        ts = ({20'd0, cpv_arr[bb]} + {20'd0, e2_arr[bb]} + {20'd0, cpmu_arr[bb]});
                        if (ts >= Q) begin
                            td = ts - {20'd0, Q};
                            if (td >= Q) td = td - {20'd0, Q};
                            cpv_arr[bb] = td[11:0];
                        end else begin
                            cpv_arr[bb] = ts[11:0];
                        end
                    end
                    cnt <= 4'd0;
                    comp_mode <= 1'b0;
                    comp_d <= 4'd10;
                    comp_start <= 1'b1;
                    phase <= PHASE_CENC;
                end
                PHASE_CENC: begin
                    if (comp_done) begin
                        pk_mode <= 1'b0;
                        pk_d <= 4'd10;
                        pk_start <= 1'b1;
                        phase <= PHASE_CENC2;
                    end
                end
                PHASE_CENC2: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 320; bb = bb + 1) cp_byte[320*cnt[1:0] + bb] = pk_bytes[3071-8*bb -: 8];
                        if (cnt == 4'd2) begin
                            cnt <= 4'd0;
                            comp_mode <= 1'b0;
                            comp_d <= 4'd4;
                            comp_start <= 1'b1;
                            phase <= PHASE_CVENC;
                        end else begin
                            cnt <= cnt + 4'd1;
                            comp_start <= 1'b1;
                            phase <= PHASE_CENC;
                        end
                    end
                end
                PHASE_CVENC: begin
                    if (comp_done) begin
                        pk_mode <= 1'b0;
                        pk_d <= 4'd4;
                        pk_start <= 1'b1;
                        phase <= PHASE_CVENC2;
                    end
                end
                PHASE_CVENC2: begin
                    if (pk_done) begin
                        for (bb = 0; bb < 128; bb = bb + 1) cp_byte[960 + bb] = pk_bytes[3071-8*bb -: 8];
                        phase <= PHASE_CMP;
                    end
                end
                PHASE_CMP: begin
                    k_out <= cmp_eq ? kp_reg : {kbar_byte[0], kbar_byte[1], kbar_byte[2], kbar_byte[3],
                        kbar_byte[4], kbar_byte[5], kbar_byte[6], kbar_byte[7],
                        kbar_byte[8], kbar_byte[9], kbar_byte[10], kbar_byte[11],
                        kbar_byte[12], kbar_byte[13], kbar_byte[14], kbar_byte[15],
                        kbar_byte[16], kbar_byte[17], kbar_byte[18], kbar_byte[19],
                        kbar_byte[20], kbar_byte[21], kbar_byte[22], kbar_byte[23],
                        kbar_byte[24], kbar_byte[25], kbar_byte[26], kbar_byte[27],
                        kbar_byte[28], kbar_byte[29], kbar_byte[30], kbar_byte[31]};
                    busy <= 1'b0;
                    done <= 1'b1;
                    phase <= PHASE_IDLE;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    always @(*) begin
        cmp_eq = 1'b1;
        for (bb = 0; bb < 1088; bb = bb + 1) begin
            if (cp_byte[bb] != c_byte[bb]) cmp_eq = 1'b0;
        end
    end

    assign shk_req = {cbd_req, sntt_req, j_req, g_req};
    assign shk_cfg = {cbd_cfg, sntt_cfg, {4'd1, 2'd1, 12'd1120}, {4'd1, 2'd3, 12'd64}};
    assign shk_blk_valid = g_bv | j_bv | sntt_bv | cbd_bv;
    assign shk_blk_data = ({1344{g_bv}} & g_bd) | ({1344{j_bv}} & j_bd) | ({1344{sntt_bv}} & sntt_bd) | ({1344{cbd_bv}} & cbd_bd);
    assign shk_out_ready = g_or | j_or | sntt_or | cbd_or;
endmodule
