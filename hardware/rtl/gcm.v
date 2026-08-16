module gcm (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [255:0]  key,
    input  wire [95:0]   nonce,
    input  wire [127:0]  aad,
    input  wire [4:0]    aad_len,
    input  wire [7:0]    pt_len,
    input  wire          pt_valid,
    output wire          pt_ready,
    input  wire [127:0]  pt_data,
    output wire          ct_valid,
    input  wire          ct_ready,
    output wire [127:0]  ct_data,
    output reg           tag_valid,
    output reg  [127:0]  tag,
    output reg           busy,
    output reg           done
);

    localparam PHASE_IDLE    = 3'd0;
    localparam PHASE_AES_H   = 3'd1;
    localparam PHASE_AES_J0  = 3'd2;
    localparam PHASE_GH_INIT = 3'd3;
    localparam PHASE_AES_CB  = 3'd4;
    localparam PHASE_GH_LEN  = 3'd5;

    reg [2:0] phase;
    reg [127:0] h_reg;
    reg [127:0] tag_mask;
    reg [127:0] ct_reg [0:15];
    reg [127:0] pt_buf [0:15];
    reg [4:0] na;
    reg [4:0] nb;
    reg [4:0] pt_cnt;
    reg [4:0] cnt_done;
    reg [5:0] ghcnt;
    reg [4:0] gh_pending;
    reg       gh_feed_r;
    reg aes_start_a;
    reg aes_start_b;
    reg gh_start;
    reg [127:0] aes_block_a;
    reg [127:0] aes_block_b;
    reg       aes_pending_a;
    reg       aes_pending_b;
    reg [4:0] aes_blk_a;
    reg [4:0] aes_blk_b;
    reg [4:0] ct_idx;
    reg [15:0] ct_vld;
    wire gh_data_valid;

    wire aes_done_a;
    wire aes_busy_a;
    wire [127:0] aes_out_a;
    wire aes_done_b;
    wire aes_busy_b;
    wire [127:0] aes_out_b;
    wire gh_done;
    wire gh_busy;
    wire [127:0] gh_tag;
    wire [1919:0] ksch_out_a;

    aes256_core u_aes_a (
        .clk(clk), .rst_n(rst_n),
        .start(aes_start_a), .key(key), .block_in(aes_block_a),
        .busy(aes_busy_a), .done(aes_done_a), .block_out(aes_out_a),
        .key_mode(1'b1), .ksch_in(1920'd0), .ksch_out(ksch_out_a)
    );

    aes256_core u_aes_b (
        .clk(clk), .rst_n(rst_n),
        .start(aes_start_b), .key(key), .block_in(aes_block_b),
        .busy(aes_busy_b), .done(aes_done_b), .block_out(aes_out_b),
        .key_mode(1'b0), .ksch_in(ksch_out_a), .ksch_out()
    );

    wire [4:0] nct = {1'b0, pt_len[7:4]} + {4'd0, |pt_len[3:0]};

    ghash u_ghash (
        .clk(clk), .rst_n(rst_n),
        .start(gh_start), .h(h_reg), .data_in(gh_data_in),
        .data_valid(gh_data_valid), .nblocks(8'd2 + {3'd0, nct}),
        .busy(gh_busy), .done(gh_done), .tag(gh_tag)
    );

    wire [127:0] len_block = { {56'd0, aad_len, 3'd0}, {53'd0, pt_len, 3'd0} };
    wire [127:0] aad_pad = aad & (128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF << (128 - {3'd0, aad_len, 3'd0}));

    wire [3:0] gh_ck = ghcnt[3:0] - 4'd1;
    wire [8:0] gh_rem9 = {1'b0, pt_len} - {gh_ck, 4'd0};
    wire [4:0] gh_cnb = (gh_rem9[8]) ? 5'd0 : ((gh_rem9[7:0] > 8'd16) ? 5'd16 : gh_rem9[4:0]);
    wire [127:0] gh_ct = ct_reg[gh_ck] & (128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF << (128 - {2'd0, gh_cnb, 3'd0}));
    wire [127:0] gh_data_in = (ghcnt == 6'd0) ? aad_pad
                             : ((ghcnt <= {1'b0, nct}) ? gh_ct : len_block);

    wire [4:0] cd_next = cnt_done + {4'd0, aes_done_a} + {4'd0, aes_done_b};
    wire [4:0] gp_next = gh_pending + {3'd0, aes_done_a} + {3'd0, aes_done_b}
                         - (gh_pending > 5'd0 ? 5'd1 : 5'd0);
    wire gh_feed = (phase == PHASE_AES_CB) && (gh_pending > 5'd0);
    wire [5:0] gc_next = ghcnt + {5'd0, gh_feed_r};
    assign gh_data_valid = (phase == PHASE_GH_LEN) ? 1'b1 : gh_feed_r;

    wire can_sa = (phase == PHASE_AES_CB) && !aes_pending_a && (na < nct) && (pt_cnt > na);
    wire can_sb = (phase == PHASE_AES_CB) && !aes_pending_b && (nb < nct) && (pt_cnt > nb);
    assign pt_ready = (phase == PHASE_AES_CB) && (pt_cnt < nct) && (pt_cnt < 5'd16)
                      && ((!aes_pending_a && (na < nct)) || (!aes_pending_b && (nb < nct)));
    assign ct_valid = (phase == PHASE_AES_CB) && ct_vld[ct_idx[3:0]];
    assign ct_data = ct_reg[ct_idx[3:0]];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            tag_valid <= 1'b0;
            aes_start_a <= 1'b0;
            aes_start_b <= 1'b0;
            gh_start <= 1'b0;
            gh_feed_r <= 1'b0;
            na <= 5'd0;
            nb <= 5'd0;
            pt_cnt <= 5'd0;
            cnt_done <= 5'd0;
            ghcnt <= 6'd0;
            gh_pending <= 5'd0;
            h_reg <= 128'd0;
            tag_mask <= 128'd0;
            aes_pending_a <= 1'b0;
            aes_pending_b <= 1'b0;
            aes_blk_a <= 5'd0;
            aes_blk_b <= 5'd0;
            ct_idx <= 5'd0;
            ct_vld <= 16'd0;
        end else begin
            done <= 1'b0;
            tag_valid <= 1'b0;
            aes_start_a <= 1'b0;
            aes_start_b <= 1'b0;
            gh_start <= 1'b0;
            gh_feed_r <= gh_feed;
            if (pt_valid && pt_ready) begin
                pt_buf[pt_cnt[3:0]] <= pt_data;
                pt_cnt <= pt_cnt + 5'd1;
            end
            if (ct_valid && ct_ready) begin
                ct_vld[ct_idx[3:0]] <= 1'b0;
                ct_idx <= ct_idx + 5'd1;
            end
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        aes_block_a <= 128'd0;
                        aes_start_a <= 1'b1;
                        busy <= 1'b1;
                        phase <= PHASE_AES_H;
                    end
                end
                PHASE_AES_H: begin
                    if (aes_done_a) begin
                        h_reg <= aes_out_a;
                        aes_block_a <= {nonce, 31'b0, 1'b1};
                        aes_start_a <= 1'b1;
                        phase <= PHASE_AES_J0;
                    end
                end
                PHASE_AES_J0: begin
                    if (aes_done_a) begin
                        tag_mask <= aes_out_a;
                        gh_start <= 1'b1;
                        ghcnt <= 6'd0;
                        gh_pending <= 5'd0;
                        gh_feed_r <= 1'b0;
                        cnt_done <= 5'd0;
                        pt_cnt <= 5'd0;
                        ct_idx <= 5'd0;
                        ct_vld <= 16'd0;
                        na <= 5'd0;
                        nb <= 5'd1;
                        aes_pending_a <= 1'b0;
                        aes_pending_b <= 1'b0;
                        phase <= PHASE_GH_INIT;
                    end
                end
                PHASE_GH_INIT: begin
                    gh_start <= 1'b1;
                    ghcnt <= 6'd0;
                    gh_pending <= 5'd1;
                    phase <= PHASE_AES_CB;
                end
                PHASE_AES_CB: begin
                    cnt_done <= cd_next;
                    gh_pending <= gp_next;
                    ghcnt <= gc_next;
                    if (can_sa) begin
                        aes_blk_a <= na;
                        aes_block_a <= {nonce, {27'd0, na} + 32'd2};
                        aes_start_a <= 1'b1;
                        aes_pending_a <= 1'b1;
                        na <= na + 5'd2;
                    end
                    if (can_sb) begin
                        aes_blk_b <= nb;
                        aes_block_b <= {nonce, {27'd0, nb} + 32'd2};
                        aes_start_b <= 1'b1;
                        aes_pending_b <= 1'b1;
                        nb <= nb + 5'd2;
                    end
                    if (aes_done_a) begin
                        ct_reg[aes_blk_a[3:0]] <= aes_out_a ^ pt_buf[aes_blk_a[3:0]];
                        ct_vld[aes_blk_a[3:0]] <= 1'b1;
                        aes_pending_a <= 1'b0;
                    end
                    if (aes_done_b) begin
                        ct_reg[aes_blk_b[3:0]] <= aes_out_b ^ pt_buf[aes_blk_b[3:0]];
                        ct_vld[aes_blk_b[3:0]] <= 1'b1;
                        aes_pending_b <= 1'b0;
                    end
                    if (cnt_done >= nct && gh_pending == 5'd0 &&
                        ct_idx == nct && pt_cnt == nct) begin
                        ghcnt <= {1'b0, nct} + 6'd1;
                        phase <= PHASE_GH_LEN;
                    end
                end
                PHASE_GH_LEN: begin
                    if (gh_done) begin
                        tag <= gh_tag ^ tag_mask;
                        tag_valid <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
