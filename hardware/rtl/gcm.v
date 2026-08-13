module gcm (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [255:0]  key,
    input  wire [95:0]   nonce,
    input  wire [127:0]  aad,
    input  wire [4:0]    aad_len,
    input  wire [7:0]    pt_len,
    input  wire [2047:0] plaintext_in,
    output reg           busy,
    output reg           done,
    output wire [2047:0] ciphertext_out,
    output reg  [127:0]  tag
);

    localparam PHASE_IDLE    = 3'd0;
    localparam PHASE_AES_H   = 3'd1;
    localparam PHASE_AES_J0  = 3'd2;
    localparam PHASE_AES_CB  = 3'd3;
    localparam PHASE_GH_INIT = 3'd4;
    localparam PHASE_GH_FEED = 3'd5;

    reg [2:0] phase;
    reg [127:0] h_reg;
    reg [127:0] tag_mask;
    reg [127:0] ct_reg [0:15];
    reg [4:0] cblk;
    reg [8:0] ghcnt;
    reg [4:0] ghblk;
    reg aes_start;
    reg gh_start;
    reg gh_data_valid;
    reg [127:0] aes_block_in;
    reg [127:0] gh_data_in;

    wire aes_done;
    wire aes_busy;
    wire [127:0] aes_block_out;
    wire gh_done;
    wire gh_busy;
    wire [127:0] gh_tag;

    aes256_core u_aes (
        .clk(clk), .rst_n(rst_n),
        .start(aes_start), .key(key), .block_in(aes_block_in),
        .busy(aes_busy), .done(aes_done), .block_out(aes_block_out)
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

    genvar gk;
    generate
        for (gk = 0; gk < 16; gk = gk + 1) begin : gct
            assign ciphertext_out[2047-128*gk -: 128] = ct_reg[gk];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            aes_start <= 1'b0;
            gh_start <= 1'b0;
            gh_data_valid <= 1'b0;
            ghcnt <= 9'd0;
            cblk <= 5'd0;
            ghblk <= 5'd0;
            h_reg <= 128'd0;
            tag_mask <= 128'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        aes_block_in <= 128'd0;
                        aes_start <= 1'b1;
                        busy <= 1'b1;
                        phase <= PHASE_AES_H;
                    end
                end
                PHASE_AES_H: begin
                    aes_start <= 1'b0;
                    if (aes_done) begin
                        h_reg <= aes_block_out;
                        aes_block_in <= {nonce, 31'b0, 1'b1};
                        aes_start <= 1'b1;
                        phase <= PHASE_AES_J0;
                    end
                end
                PHASE_AES_J0: begin
                    aes_start <= 1'b0;
                    if (aes_done) begin
                        tag_mask <= aes_block_out;
                        if (nct == 5'd0) begin
                            ghcnt <= 9'd0;
                            ghblk <= 5'd0;
                            phase <= PHASE_GH_INIT;
                        end else begin
                            aes_block_in <= {nonce, 32'd2};
                            aes_start <= 1'b1;
                            cblk <= 5'd0;
                            phase <= PHASE_AES_CB;
                        end
                    end
                end
                PHASE_AES_CB: begin
                    aes_start <= 1'b0;
                    if (aes_done) begin
                        ct_reg[cblk[3:0]] <= aes_block_out ^ plaintext_in[2047-128*cblk -: 128];
                        if (cblk == nct - 5'd1) begin
                            ghcnt <= 9'd0;
                            ghblk <= 5'd0;
                            phase <= PHASE_GH_INIT;
                        end else begin
                            aes_block_in <= {nonce, {27'd0, cblk} + 32'd3};
                            aes_start <= 1'b1;
                            cblk <= cblk + 5'd1;
                        end
                    end
                end
                PHASE_GH_INIT: begin
                    gh_start <= 1'b1;
                    phase <= PHASE_GH_FEED;
                end
                PHASE_GH_FEED: begin
                    gh_start <= 1'b0;
                    if (ghcnt == 9'd0) begin
                        gh_data_valid <= 1'b1;
                        ghcnt <= 9'd1;
                    end else if (ghcnt == 9'd130) begin
                        gh_data_valid <= 1'b0;
                        if ({3'd0, ghblk} == 8'd2 + {3'd0, nct} - 8'd1) begin
                            tag <= gh_tag ^ tag_mask;
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end else begin
                            ghblk <= ghblk + 5'd1;
                            ghcnt <= 9'd0;
                        end
                    end else begin
                        gh_data_valid <= 1'b0;
                        ghcnt <= ghcnt + 9'd1;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    wire [4:0] ck = ghblk - 5'd1;
    wire [8:0] rem9 = {1'b0, pt_len} - {ck, 4'd0};
    wire [4:0] cnb = (rem9[8]) ? 5'd0 : ((rem9[7:0] > 8'd16) ? 5'd16 : rem9[4:0]);
    wire [127:0] ct_gh = ct_reg[ghblk[3:0] - 4'd1] & (128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF << (128 - {2'd0, cnb, 3'd0}));

    always @(*) begin
        if (ghblk == 5'd0)
            gh_data_in = aad_pad;
        else if (ghblk <= nct)
            gh_data_in = ct_gh;
        else
            gh_data_in = len_block;
    end

endmodule
