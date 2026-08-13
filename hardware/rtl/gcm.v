module gcm (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [255:0]  key,
    input  wire [95:0]   nonce,
    input  wire [127:0]  aad,
    input  wire [1023:0] plaintext_in,
    output reg           busy,
    output reg           done,
    output wire [1023:0] ciphertext_out,
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
    reg [127:0] ct_reg [0:7];
    reg [3:0] cblk;
    reg [8:0] ghcnt;
    reg [3:0] ghblk;
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

    ghash u_ghash (
        .clk(clk), .rst_n(rst_n),
        .start(gh_start), .h(h_reg), .data_in(gh_data_in),
        .data_valid(gh_data_valid), .nblocks(8'd10),
        .busy(gh_busy), .done(gh_done), .tag(gh_tag)
    );

    wire [127:0] len_block = {64'h0000000000000080, 64'h0000000000000400};

    genvar gk;
    generate
        for (gk = 0; gk < 8; gk = gk + 1) begin : gct
            assign ciphertext_out[1023-128*gk -: 128] = ct_reg[gk];
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
            cblk <= 4'd0;
            ghblk <= 4'd0;
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
                        aes_block_in <= {nonce, 32'd2};
                        aes_start <= 1'b1;
                        cblk <= 4'd0;
                        phase <= PHASE_AES_CB;
                    end
                end
                PHASE_AES_CB: begin
                    aes_start <= 1'b0;
                    if (aes_done) begin
                        ct_reg[cblk[2:0]] <= aes_block_out ^ plaintext_in[1023-128*cblk -: 128];
                        if (cblk == 4'd7) begin
                            ghcnt <= 9'd0;
                            ghblk <= 4'd0;
                            phase <= PHASE_GH_INIT;
                        end else begin
                            aes_block_in <= {nonce, {28'd0, cblk} + 32'd3};
                            aes_start <= 1'b1;
                            cblk <= cblk + 4'd1;
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
                        if (ghblk == 4'd9) begin
                            tag <= gh_tag ^ tag_mask;
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end else begin
                            ghblk <= ghblk + 4'd1;
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

    always @(*) begin
        case (ghblk)
            4'd0: gh_data_in = aad;
            4'd1: gh_data_in = ct_reg[0];
            4'd2: gh_data_in = ct_reg[1];
            4'd3: gh_data_in = ct_reg[2];
            4'd4: gh_data_in = ct_reg[3];
            4'd5: gh_data_in = ct_reg[4];
            4'd6: gh_data_in = ct_reg[5];
            4'd7: gh_data_in = ct_reg[6];
            4'd8: gh_data_in = ct_reg[7];
            default: gh_data_in = len_block;
        endcase
    end

endmodule
