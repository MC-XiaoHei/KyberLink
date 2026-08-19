module gcm_stream (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
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
    input  wire [127:0]  tag_in,
    output wire          tag_ok,
    output reg           busy,
    output reg           done
);

    localparam PHASE_IDLE    = 3'd0;
    localparam PHASE_AES_H   = 3'd1;
    localparam PHASE_AES_J0  = 3'd2;
    localparam PHASE_AES_CB  = 3'd3;
    localparam PHASE_GH_LEN  = 3'd4;

    reg [2:0] phase;
    reg [127:0] h_reg;
    reg [127:0] tag_mask;
    reg [127:0] blk_in;
    reg [127:0] pending_pt;
    reg         got;
    reg         aes_start;
    reg         aes_key_load;
    reg [1:0]   inflight;
    reg         gh_start;
    reg [7:0]   ghcnt;
    reg         gh_aad_pend;
    reg [127:0] gh_q [0:1];
    reg [1:0]   gh_qcnt;
    reg         gh_qwr;
    reg         gh_qrd;
    reg [127:0] out_blk;
    reg         out_valid;
    reg [7:0]   cntr;
    reg [127:0] aes_block;

    wire aes_done;
    wire aes_busy;
    wire [127:0] aes_out;
    wire gh_done;
    wire gh_busy;
    wire gh_ready;
    wire gh_accept;
    wire [127:0] gh_tag;

    aes256_core u_aes (
        .clk(clk), .rst_n(rst_n),
        .start(aes_start), .key(key), .block_in(aes_block),
        .busy(aes_busy), .done(aes_done), .block_out(aes_out),
        .key_mode(1'b1), .key_load(aes_key_load), .ksch_in(1920'd0), .ksch_out()
    );

    wire [8:0] nct = {1'b0, pt_len[11:4]} + {8'd0, |pt_len[3:0]};

    ghash u_ghash (
        .clk(clk), .rst_n(rst_n),
        .start(gh_start), .h(h_reg), .data_in(gh_data_in),
        .data_valid(gh_data_valid), .nblocks(8'd2 + nct[7:0]),
        .busy(gh_busy), .done(gh_done), .ready(gh_ready), .block_done(), .accept(gh_accept),
        .tag(gh_tag)
    );

    wire [127:0] len_block = { {56'd0, aad_len, 3'd0}, {49'd0, pt_len, 3'd0} };
    wire [127:0] aad_pad = aad & (128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF << (128 - {3'd0, aad_len, 3'd0}));

    wire [127:0] gh_feed_data = decrypt ? blk_in : (aes_out ^ blk_in);
    wire [4:0] last_nb = |pt_len[3:0] ? {1'b0, pt_len[3:0]} : 5'd16;
    wire [4:0] blk_nb = (ghcnt[7:0] == nct[7:0]) ? last_nb : 5'd16;
    wire [127:0] gh_masked = gh_q[gh_qrd] &
        (128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF << (128 - {2'd0, blk_nb, 3'd0}));
    wire [127:0] gh_data_in = (ghcnt == 8'd0) ? aad_pad :
                              ((ghcnt <= nct[7:0]) ? gh_masked : len_block);
    wire gh_do_feed = gh_ready && gh_busy && (gh_aad_pend || (gh_qcnt > 2'd0) ||
                                              (phase == PHASE_GH_LEN));
    wire gh_data_valid = gh_do_feed;

    assign pt_ready = (phase == PHASE_AES_CB) && !got && (inflight < 2'd2);
    assign ct_valid = out_valid;
    assign ct_data  = out_blk;
    assign tag_ok = tag_valid && decrypt && ((gh_tag ^ tag_mask) == tag_in);

    wire cb_submit = (phase == PHASE_AES_CB) && !out_valid && got &&
        (gh_qcnt < 2'd2) &&
        ({1'b0, cntr} + {7'd0, inflight}) < nct &&
        ((inflight == 2'd0) || (aes_done && (inflight == 2'd1)));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            tag_valid <= 1'b0;
            aes_start <= 1'b0;
            aes_key_load <= 1'b0;
            inflight <= 2'd0;
            gh_start <= 1'b0;
            got <= 1'b0;
            gh_qcnt <= 2'd0;
            gh_qwr <= 1'b0;
            gh_qrd <= 1'b0;
            gh_aad_pend <= 1'b0;
            ghcnt <= 8'd0;
            cntr <= 8'd0;
            h_reg <= 128'd0;
            tag_mask <= 128'd0;
            blk_in <= 128'd0;
            out_blk <= 128'd0;
            out_valid <= 1'b0;
            aes_block <= 128'd0;
        end else begin
            done <= 1'b0;
            aes_start <= 1'b0;
            gh_start <= 1'b0;
            if (pt_valid && pt_ready) begin
                blk_in <= pt_data;
                got <= 1'b1;
            end
            if (out_valid && ct_ready) begin
                out_valid <= 1'b0;
            end
            if (gh_do_feed) begin
                if (gh_aad_pend) begin
                    gh_aad_pend <= 1'b0;
                end else begin
                    gh_qrd <= gh_qrd ^ 1'b1;
                end
                ghcnt <= ghcnt + 8'd1;
            end
            if ((phase == PHASE_AES_CB) && ((!decrypt && aes_done) ||
                                            (decrypt && pt_valid && pt_ready))) begin
                gh_qwr <= gh_qwr ^ 1'b1;
            end
            gh_qcnt <= gh_qcnt + ((phase == PHASE_AES_CB) &&
                                  ((!decrypt && aes_done) ||
                                   (decrypt && pt_valid && pt_ready)) ? 2'd1 : 2'd0)
                      - ((gh_do_feed && !gh_aad_pend && (phase != PHASE_GH_LEN)) ? 2'd1 : 2'd0);
            if (phase == PHASE_AES_CB)
                inflight <= inflight + (cb_submit && !aes_done ? 2'd1 : 2'd0)
                          - (aes_done && !cb_submit ? 2'd1 : 2'd0);
            case (phase)
                PHASE_IDLE: begin
                    tag_valid <= 1'b0;
                    if (start) begin
                        aes_block <= 128'd0;
                        blk_in <= 128'd0;
                        aes_start <= 1'b1;
                        aes_key_load <= 1'b1;
                        inflight <= 2'd1;
                        busy <= 1'b1;
                        phase <= PHASE_AES_H;
                    end
                end
                PHASE_AES_H: begin
                    if (aes_done) begin
                        h_reg <= aes_out;
                        aes_block <= {nonce, 31'b0, 1'b1};
                        aes_start <= 1'b1;
                        aes_key_load <= 1'b0;
                        phase <= PHASE_AES_J0;
                    end
                end
                PHASE_AES_J0: begin
                    if (aes_done) begin
                        tag_mask <= aes_out;
                        gh_start <= 1'b1;
                        ghcnt <= 8'd0;
                        gh_aad_pend <= 1'b1;
                        gh_qcnt <= 2'd0;
                        gh_qwr <= 1'b0;
                        gh_qrd <= 1'b0;
                        got <= 1'b0;
                        inflight <= 2'd0;
                        cntr <= 8'd0;
                        out_valid <= 1'b0;
                        phase <= PHASE_AES_CB;
                    end
                end
                PHASE_AES_CB: begin
                    if (cb_submit) begin
                        aes_block <= {nonce, {24'd0, cntr} + {30'd0, inflight} + 32'd2};
                        pending_pt <= blk_in;
                        aes_start <= 1'b1;
                        got <= 1'b0;
                    end
                    if (aes_done) begin
                        out_blk <= aes_out ^ pending_pt;
                        if (!decrypt) begin
                            gh_q[gh_qwr] <= aes_out ^ pending_pt;
                        end
                        out_valid <= 1'b1;
                        cntr <= cntr + 8'd1;
                    end
                    if (decrypt && pt_valid && pt_ready) begin
                        gh_q[gh_qwr] <= pt_data;
                    end
                    if ((cntr >= nct[7:0]) && (inflight == 2'd0) && (gh_qcnt == 2'd0) &&
                        (ghcnt >= (nct[7:0] + 8'd1))) begin
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
