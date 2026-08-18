module esp_rx (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [7:0]    s_tdata,
    input  wire          s_tvalid,
    input  wire          s_tlast,
    output wire          s_tready,

    input  wire [255:0]  key,
    output reg  [2047:0] plaintext_out,
    output reg  [7:0]    plaintext_len,
    output reg           plaintext_valid,
    output reg           tag_ok,
    output reg           busy,
    output reg           done
);

    localparam ST_IDLE = 2'd0;
    localparam ST_RX   = 2'd1;
    localparam ST_GCM  = 2'd2;
    localparam ST_OUT  = 2'd3;

    reg [1:0] state;

    reg [9:0]  cnt;
    reg [31:0] spi_r;
    reg [31:0] seq_r;
    reg [95:0] iv_r;
    (* syn_ramstyle = "registers" *) reg [127:0] ct_blk [0:19];
    reg [143:0] tail18;
    reg [7:0]  ct_len;
    reg [4:0]  nct;

    reg        gcm_start;
    reg        gcm_pt_valid;
    reg        gcm_ct_ready;
    reg [4:0]  ct_idx;
    (* syn_ramstyle = "registers" *) reg [127:0] pt_buf [0:15];

    wire gcm_pt_ready;
    wire gcm_ct_valid;
    wire [127:0] gcm_ct_data;
    wire gcm_busy;
    wire gcm_done;
    wire gcm_tag_ok;

    wire [127:0] tag_w = tail18[127:0];

    wire [2047:0] pt_out_w =
        {pt_buf[0], pt_buf[1], pt_buf[2], pt_buf[3],
         pt_buf[4], pt_buf[5], pt_buf[6], pt_buf[7],
         pt_buf[8], pt_buf[9], pt_buf[10], pt_buf[11],
         pt_buf[12], pt_buf[13], pt_buf[14], pt_buf[15]};

    wire gcm_shift = gcm_pt_valid && gcm_pt_ready;

    gcm u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(gcm_start), .key(key), .nonce(iv_r),
        .aad({spi_r, seq_r, 64'b0}), .aad_len(5'd8),
        .pt_len(ct_len),
        .pt_valid(gcm_pt_valid), .pt_ready(gcm_pt_ready), .pt_data(ct_blk[0]),
        .ct_valid(gcm_ct_valid), .ct_ready(gcm_ct_ready), .ct_data(gcm_ct_data),
        .tag_valid(), .tag(),
        .decrypt(1'b1), .tag_in(tag_w), .tag_ok(gcm_tag_ok),
        .busy(gcm_busy), .done(gcm_done)
    );

    assign s_tready = (state == ST_IDLE) || (state == ST_RX);

    wire [9:0] rtotal = cnt + 10'd1;
    wire [9:0] rct9 = rtotal - 10'd38;
    wire [9:0] ct_off = cnt - 10'd20;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            cnt <= 10'd0;
            spi_r <= 32'd0;
            seq_r <= 32'd0;
            iv_r <= 96'd0;
            tail18 <= 144'd0;
            ct_len <= 8'd0;
            nct <= 5'd0;
            gcm_start <= 1'b0;
            gcm_pt_valid <= 1'b0;
            gcm_ct_ready <= 1'b0;
            ct_idx <= 5'd0;
            plaintext_out <= 2048'd0;
            plaintext_len <= 8'd0;
            plaintext_valid <= 1'b0;
            tag_ok <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;
            plaintext_valid <= 1'b0;
            gcm_start <= 1'b0;
            gcm_pt_valid <= 1'b0;
            gcm_ct_ready <= 1'b0;
            if (s_tvalid) begin
                tail18 <= {tail18[135:0], s_tdata};
                if (cnt < 10'd4)
                    spi_r[31 - 8*cnt[1:0] -: 8] <= s_tdata;
                else if (cnt < 10'd8)
                    seq_r[31 - 8*(cnt - 10'd4) -: 8] <= s_tdata;
                else if (cnt < 10'd20)
                    iv_r[95 - 8*(cnt - 10'd8) -: 8] <= s_tdata;
                else
                    ct_blk[ct_off >> 4][127 - 8*ct_off[3:0] -: 8] <= s_tdata;
            end
            if (gcm_shift) begin
                ct_blk[0] <= ct_blk[1];
                ct_blk[1] <= ct_blk[2];
                ct_blk[2] <= ct_blk[3];
                ct_blk[3] <= ct_blk[4];
                ct_blk[4] <= ct_blk[5];
                ct_blk[5] <= ct_blk[6];
                ct_blk[6] <= ct_blk[7];
                ct_blk[7] <= ct_blk[8];
                ct_blk[8] <= ct_blk[9];
                ct_blk[9] <= ct_blk[10];
                ct_blk[10] <= ct_blk[11];
                ct_blk[11] <= ct_blk[12];
                ct_blk[12] <= ct_blk[13];
                ct_blk[13] <= ct_blk[14];
                ct_blk[14] <= ct_blk[15];
                ct_blk[15] <= 128'd0;
            end
            case (state)
                ST_IDLE: begin
                    if (s_tvalid) begin
                        cnt <= 10'd1;
                        busy <= 1'b1;
                        state <= ST_RX;
                    end
                end
                ST_RX: begin
                    if (s_tvalid) begin
                        if (s_tlast) begin
                            if (rtotal > 10'd293) begin
                                busy <= 1'b0;
                                cnt <= 10'd0;
                                state <= ST_IDLE;
                            end else begin
                                ct_len <= rct9[7:0];
                                nct <= rct9[7:4] + {4'd0, |rct9[3:0]};
                                ct_idx <= 5'd0;
                                gcm_start <= 1'b1;
                                state <= ST_GCM;
                            end
                        end else begin
                            cnt <= cnt + 10'd1;
                        end
                    end
                end
                ST_GCM: begin
                    if (gcm_pt_ready && !gcm_pt_valid) begin
                        gcm_pt_valid <= 1'b1;
                    end else if (gcm_pt_valid && gcm_pt_ready) begin
                        gcm_pt_valid <= 1'b0;
                    end
                    if (gcm_ct_valid && (ct_idx < nct)) begin
                        pt_buf[ct_idx[3:0]] <= gcm_ct_data;
                        ct_idx <= ct_idx + 5'd1;
                    end
                    gcm_ct_ready <= (gcm_ct_valid && (ct_idx < nct));
                    if (gcm_done) begin
                        plaintext_out <= pt_out_w;
                        plaintext_len <= ct_len;
                        tag_ok <= gcm_tag_ok;
                        state <= ST_OUT;
                    end
                end
                ST_OUT: begin
                    plaintext_valid <= 1'b1;
                    busy <= 1'b0;
                    done <= 1'b1;
                    cnt <= 10'd0;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
