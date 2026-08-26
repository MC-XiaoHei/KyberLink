module gcm_stream (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire          key_refresh,
    input  wire [255:0]  key,
    input  wire [95:0]   nonce,
    input  wire [127:0]  aad,
    input  wire [4:0]    aad_len,
    input  wire [11:0]   pt_len,
    input  wire          pt_valid,
    output wire          pt_ready,
    input  wire [127:0]  pt_data,
    output wire          ct_valid,
    input  wire          ct_ready,
    output wire [127:0]  ct_data,
    output reg           tag_valid,
    output reg  [127:0]  tag,
    input  wire          decrypt,
    output reg           busy,
    output reg           done,
    output wire          idle
);

    assign idle = (phase == PHASE_IDLE) && !busy;

    localparam PHASE_IDLE    = 3'd0;
    localparam PHASE_AES_H   = 3'd1;
    localparam PHASE_AES_J0  = 3'd2;
    localparam PHASE_AES_CB  = 3'd3;
    localparam PHASE_GH_LEN  = 3'd4;

    reg [2:0] phase;
    reg [2:0] phase_d;
    reg       h_submit;
    reg       j0_submit;
    always @(posedge clk) begin
        phase_d <= phase;
    end
    reg [127:0] h_reg;
    reg [127:0] tag_mask;
    reg         aes_start;
    reg         aes_key_load;
    reg         gh_start;
    reg [7:0]   ghcnt;
    reg         gh_aad_pend;
    reg [127:0] gh_q [0:3];
    reg [2:0]   gh_qcnt;
    reg [1:0]   gh_qwr;
    reg [1:0]   gh_qrd;
    reg [127:0] out_q [0:3];
    reg [1:0]   out_wr;
    reg [1:0]   out_rd;
    reg [2:0]   out_cnt;
    reg [7:0]   cntr;
    reg [127:0] pending_q [0:3];
    reg [1:0]   pending_wr;
    reg [1:0]   pending_rd;
    reg [127:0] pt_fifo [0:3];
    reg [1:0]   pt_wr;
    reg [1:0]   pt_rd;
    reg [2:0]   pt_cnt;

    wire aes_done;
    wire aes_busy;
    wire aes_crypt_rdy;
    reg aes_crypt_rdy_q;
    wire aes_load_rdy;
    wire [127:0] aes_out;
    wire gh_done;
    wire gh_busy;
    wire gh_ready;
    wire gh_accept;
    wire [127:0] gh_tag;

    aes256_core_pipe u_aes (
        .clk(clk), .rst_n(rst_n),
        .start(aes_start), .key(key), .block_in(aes_block_w),
        .blk_valid(blk_valid_w),
        .busy(aes_busy), .crypt_rdy(aes_crypt_rdy), .load_rdy(aes_load_rdy), .done(aes_done), .block_out(aes_out),
        .key_mode(1'b1), .key_load(aes_key_load), .ksch_in(1920'd0), .ksch_out()
    );

    reg [8:0]   nct_r;
    reg [11:0]  pt_len_r;
    reg [4:0]   last_nb_r;
    wire cb_h  = (phase == PHASE_AES_H) && !h_submit && aes_load_rdy && !aes_done;
    wire cb_j0 = (phase == PHASE_AES_J0) && !j0_submit && aes_load_rdy && !aes_done;
    wire blk_valid_w = cb_h || cb_j0 || cb_submit;
    wire [127:0] aes_block_w = cb_h ? 128'd0 :
                  cb_j0 ? {nonce, 31'b0, 1'b1} :
                  {nonce, {24'd0, cntr} + 32'd2};

    ghash u_ghash (
        .clk(clk), .rst_n(rst_n),
        .start(gh_start), .h(h_reg), .data_in(gh_data_in),
        .data_valid(gh_data_valid), .nblocks(8'd2 + nct_r[7:0]),
        .busy(gh_busy), .done(gh_done), .ready(gh_ready), .block_done(), .accept(gh_accept),
        .tag(gh_tag)
    );

    wire [127:0] len_block = { {56'd0, aad_len, 3'd0}, {49'd0, pt_len_r, 3'd0} };
    wire [127:0] aad_pad = aad & (128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF << (128 - {3'd0, aad_len, 3'd0}));

    wire [4:0] blk_nb = (ghcnt[7:0] == nct_r[7:0]) ? last_nb_r : 5'd16;
    wire [127:0] gh_masked = gh_q[gh_qrd] &
        (128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF << (128 - {2'd0, blk_nb, 3'd0}));
    wire [127:0] gh_data_in = (ghcnt == 8'd0) ? aad_pad :
                              ((ghcnt <= nct_r[7:0]) ? gh_masked : len_block);
    wire gh_do_feed = gh_ready && gh_busy && (gh_aad_pend || (gh_qcnt > 3'd0) ||
                                              (phase == PHASE_GH_LEN));
    wire gh_data_valid = gh_do_feed;

    wire cb_avail = (pt_cnt >= 3'd1);
    wire out_room = (out_cnt + 3'd1) <= 3'd4;
    assign pt_ready = (phase == PHASE_AES_CB) && aes_crypt_rdy_q &&
                      (gh_qcnt < 3'd3) && (pt_cnt < 3'd4);
    assign ct_valid = (out_cnt != 3'd0);
    assign ct_data  = out_q[out_rd];

    wire cb_submit = (phase == PHASE_AES_CB) && out_room && cb_avail &&
        (gh_qcnt < 3'd2) && aes_load_rdy && !aes_start && !aes_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            tag_valid <= 1'b0;
            aes_start <= 1'b0;
            aes_key_load <= 1'b0;
            gh_start <= 1'b0;
            gh_qcnt <= 3'd0;
            gh_qwr <= 2'd0;
            gh_qrd <= 2'd0;
            gh_aad_pend <= 1'b0;
            ghcnt <= 8'd0;
            cntr <= 8'd0;
            h_reg <= 128'd0;
            tag_mask <= 128'd0;
            out_wr <= 2'd0;
            out_rd <= 2'd0;
            out_cnt <= 3'd0;
            pending_wr <= 2'd0;
            pending_rd <= 2'd0;
            pt_wr <= 2'd0;
            pt_rd <= 2'd0;
            pt_cnt <= 3'd0;
            nct_r <= 9'd0;
            pt_len_r <= 12'd0;
            last_nb_r <= 5'd0;
            aes_crypt_rdy_q <= 1'b0;
        end else begin
            done <= 1'b0;
            aes_start <= 1'b0;
            gh_start <= 1'b0;
            aes_crypt_rdy_q <= aes_crypt_rdy;
            if (pt_valid && pt_ready) begin
                pt_fifo[pt_wr] <= pt_data;
                pt_wr <= pt_wr + 2'd1;
            end
            if (aes_done) begin
                if (h_submit) begin
                    h_reg <= aes_out;
                    aes_key_load <= 1'b0;
                    h_submit <= 1'b0;
                end else if (j0_submit) begin
                    tag_mask <= aes_out;
                    j0_submit <= 1'b0;
                    gh_start <= 1'b1;
                    ghcnt <= 8'd0;
                    gh_aad_pend <= 1'b1;
                    gh_qcnt <= 3'd0;
                    gh_qwr <= 2'd0;
                    gh_qrd <= 2'd0;
                    nct_r <= {1'b0, pt_len[11:4]} + {8'd0, |pt_len[3:0]};
                    pt_len_r <= pt_len;
                    last_nb_r <= |pt_len[3:0] ? {1'b0, pt_len[3:0]} : 5'd16;
                    out_wr <= 2'd0;
                    out_rd <= 2'd0;
                    out_cnt <= 3'd0;
                end else if (phase == PHASE_AES_CB) begin
                    gh_q[gh_qwr] <= decrypt ? pending_q[pending_rd] : (aes_out ^ pending_q[pending_rd]);
                    gh_qwr <= gh_qwr + 2'd1;
                    out_q[out_wr] <= aes_out ^ pending_q[pending_rd];
                    out_wr <= out_wr + 2'd1;
                    pending_rd <= pending_rd + 2'd1;
                end
            end
            if (ct_valid && ct_ready) begin
                out_rd <= out_rd + 2'd1;
            end            if (gh_do_feed) begin
                if (gh_aad_pend) begin
                    gh_aad_pend <= 1'b0;
                end else begin
                    gh_qrd <= gh_qrd + 2'd1;
                end
                ghcnt <= ghcnt + 8'd1;
            end
            pt_cnt <= pt_cnt + (pt_valid && pt_ready ? 3'd1 : 3'd0)
                            - (cb_submit ? 3'd1 : 3'd0);
            out_cnt <= out_cnt + ((aes_done && (phase == PHASE_AES_CB) && !h_submit && !j0_submit) ? 3'd1 : 3'd0)
                            - (ct_valid && ct_ready ? 3'd1 : 3'd0);
            gh_qcnt <= gh_qcnt + ((aes_done && (phase == PHASE_AES_CB) && !h_submit && !j0_submit) ? 3'd1 : 3'd0)
                            - ((gh_do_feed && !gh_aad_pend && (phase != PHASE_GH_LEN)) ? 3'd1 : 3'd0);
            case (phase)
                PHASE_IDLE: begin
                    tag_valid <= 1'b0;
                    if (start) begin
                        aes_start <= 1'b1;
                        aes_key_load <= 1'b1;
                        busy <= 1'b1;
                        phase <= PHASE_AES_H;
                    end
                end
                PHASE_AES_H: begin
                    if (cb_h) begin
                        h_submit <= 1'b1;
                        phase <= PHASE_AES_J0;
                    end
                end
                PHASE_AES_J0: begin
                    if (cb_j0) begin
                        j0_submit <= 1'b1;
                        cntr <= 8'd0;
                        pending_wr <= 2'd0;
                        pending_rd <= 2'd0;
                        pt_wr <= 2'd0;
                        pt_rd <= 2'd0;
                        pt_cnt <= 3'd0;
                        phase <= PHASE_AES_CB;
                    end
                end
                PHASE_AES_CB: begin
                    if (cb_submit) begin
                        pending_q[pending_wr] <= pt_fifo[pt_rd];
                        pending_wr <= pending_wr + 2'd1;
                        pt_rd <= pt_rd + 2'd1;
                        cntr <= cntr + 8'd1;
                    end
                    if (!j0_submit && (cntr >= nct_r[7:0]) && (gh_qcnt == 3'd0) &&
                        (ghcnt >= (nct_r[7:0] + 8'd1)) && (pt_cnt == 3'd0)) begin
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
