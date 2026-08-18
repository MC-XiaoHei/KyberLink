module esp (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [255:0]  key,
    input  wire [31:0]   spi,
    input  wire [31:0]   seq,
    input  wire [95:0]   iv,
    input  wire [7:0]    plaintext_len,
    input  wire [2047:0] plaintext_in,
    output reg           busy,
    output reg           done,
    output reg  [7:0]    tx_data,
    output reg           tx_valid,
    output reg           tx_last,
    input  wire          tx_ready
);

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_CRYPT = 2'd1;
    localparam PHASE_TX = 2'd2;

    reg [1:0] phase;
    reg [255:0] key_r;
    reg [31:0] spi_r;
    reg [31:0] seq_r;
    reg [95:0] iv_r;
    reg [7:0] pt_len_r;
    reg [2047:0] pt_r;
    reg [127:0] ct_blk [0:15];
    reg [4:0] pt_idx;
    reg [4:0] ct_idx;
    reg feeding_r;
    reg gcm_start;
    reg gcm_pt_valid;
    reg gcm_ct_ready;

    reg [8:0] tx_cnt;
    reg [127:0] ctl_r;
    reg [127:0] ctl_pre;
    reg [4:0]  ctl_b;

    wire gcm_pt_ready;
    wire gcm_ct_valid;
    wire [127:0] gcm_ct_data;
    wire gcm_tag_valid;
    wire [127:0] gcm_tag;
    wire gcm_busy;
    wire gcm_done;

    wire [127:0] pt_blk [0:15];
    wire [127:0] gcm_pt_data = pt_blk[pt_idx[3:0]];

    gcm u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(gcm_start), .key(key_r), .nonce(iv_r),
        .aad({spi_r, seq_r, 64'b0}), .aad_len(5'd8),
        .pt_len(pt_len_r),
        .pt_valid(gcm_pt_valid), .pt_ready(gcm_pt_ready), .pt_data(gcm_pt_data),
        .ct_valid(gcm_ct_valid), .ct_ready(gcm_ct_ready), .ct_data(gcm_ct_data),
        .tag_valid(gcm_tag_valid), .tag(gcm_tag),
        .decrypt(1'b0), .tag_in(128'd0), .tag_ok(),
        .busy(gcm_busy), .done(gcm_done)
    );

    wire [4:0] nct = {1'b0, pt_len_r[7:4]} + {4'd0, |pt_len_r[3:0]};
    wire [8:0] payload_end = 9'd20 + {1'b0, pt_len_r};
    wire [8:0] tag_start = payload_end + 9'd2;
    wire [8:0] tag_end = tag_start + 9'd16;
    wire [8:0] tx_last_cnt = tag_end - 9'd1;

    genvar gp;
    generate
        for (gp = 0; gp < 16; gp = gp + 1) begin : gptblk
            assign pt_blk[gp] = pt_r[2047 - 128*gp -: 128];
        end
    endgenerate

    function [7:0] hdr_byte(input [8:0] fc);
        begin
            if (fc < 9'd4)
                hdr_byte = spi_r[31 - 8*fc[1:0] -: 8];
            else if (fc < 9'd8)
                hdr_byte = seq_r[63 - 8*fc[1:0] -: 8];
            else
                hdr_byte = iv_r[95 - 8*(fc - 9'd8) -: 8];
        end
    endfunction


    wire [3:0] po = tx_cnt[3:0] - 4'd4;
    wire pfin = (tx_cnt >= 9'd20) && (tx_cnt < payload_end);
    wire pblend = pfin && (po == 4'd15);


    wire [7:0] tx_d_comb =
        (tx_cnt < 9'd20)        ? hdr_byte(tx_cnt) :
        (tx_cnt < payload_end)  ? ctl_r[127:120] :
        (tx_cnt == payload_end) ? 8'h00 :
        (tx_cnt == payload_end + 9'd1) ? 8'h04 :
        (tx_cnt < tag_end)      ? gcm_tag[127 - 8*(tx_cnt - tag_start) -: 8] :
        8'd0;

    wire [8:0] nxt = tx_cnt + 9'd1;
    wire [127:0] ctl_r_next =
        pfin
            ? (pblend ? ctl_pre : {ctl_r[119:0], 8'd0})
            : ctl_r;
    wire [8:0] ntag = nxt - tag_start;
    wire [7:0] tx_d_next =
        (nxt < 9'd20)        ? hdr_byte(nxt) :
        (nxt < payload_end)  ? ctl_r_next[127:120] :
        (nxt == payload_end) ? 8'h00 :
        (nxt == payload_end + 9'd1) ? 8'h04 :
        (nxt < tag_end)      ? gcm_tag[127 - 8*ntag[3:0] -: 8] :
        8'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            gcm_start <= 1'b0;
            gcm_pt_valid <= 1'b0;
            gcm_ct_ready <= 1'b0;
            pt_idx <= 5'd0;
            ct_idx <= 5'd0;
            feeding_r <= 1'b0;
            tx_cnt <= 9'd0;
            ctl_r <= 128'd0;
            ctl_pre <= 128'd0;
            ctl_b <= 5'd0;
            tx_data <= 8'd0;
            tx_valid <= 1'b0;
            tx_last <= 1'b0;
        end else begin
            done <= 1'b0;
            gcm_start <= 1'b0;
            gcm_pt_valid <= 1'b0;
            gcm_ct_ready <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        key_r <= key;
                        spi_r <= spi;
                        seq_r <= seq;
                        iv_r <= iv;
                        pt_len_r <= plaintext_len;
                        pt_r <= plaintext_in;
                        gcm_start <= 1'b1;
                        busy <= 1'b1;
                        pt_idx <= 5'd0;
                        ct_idx <= 5'd0;
                        ctl_b <= 5'd0;
                        phase <= PHASE_CRYPT;
                    end
                end
                PHASE_CRYPT: begin
                    if (feeding_r && gcm_pt_ready) begin
                        feeding_r <= 1'b0;
                        pt_idx <= pt_idx + 5'd1;
                        gcm_pt_valid <= 1'b0;
                    end else if (feeding_r) begin
                        gcm_pt_valid <= 1'b1;
                    end
                    if (!feeding_r && gcm_pt_ready && (pt_idx < nct)) begin
                        feeding_r <= 1'b1;
                        gcm_pt_valid <= 1'b1;
                    end
                    if (gcm_ct_valid && gcm_ct_ready &&
                        (ct_idx < nct)) begin : ct_write
                        integer k;
                        for (k = 0; k < 16; k = k + 1) begin
                            if (ct_idx[3:0] == k[3:0])
                                ct_blk[k] <= gcm_ct_data;
                        end
                        ct_idx <= ct_idx + 5'd1;
                    end
                    gcm_ct_ready <= (gcm_ct_valid && (ct_idx < nct));
                    if (gcm_tag_valid) begin
                        tx_cnt <= 9'd0;
                        ctl_r <= ct_blk[0];
                        ctl_pre <= (nct > 5'd1) ? ct_blk[1] : 128'd0;
                        ctl_b <= 5'd0;
                        tx_data <= hdr_byte(9'd0);
                        tx_valid <= 1'b1;
                        phase <= PHASE_TX;
                    end
                end
                PHASE_TX: begin
                    tx_valid <= 1'b1;
                    if (tx_ready) begin
                        if (tx_cnt == tx_last_cnt) begin
                            tx_valid <= 1'b0;
                            tx_last <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end else begin
                            tx_data <= tx_d_next;
                            tx_last <= (nxt == tx_last_cnt);
                            tx_cnt <= nxt;

                            if (pfin) begin
                                ctl_r <= ctl_r_next;
                                if (pblend) begin
                                    ctl_pre <= (ctl_b + 5'd2 < nct) ? ct_blk[ctl_b[3:0] + 4'd2] : 128'd0;
                                    ctl_b <= ctl_b + 5'd1;
                                end
                            end
                        end
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

endmodule
