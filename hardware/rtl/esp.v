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
    output wire [2343:0] frame_out
);

    localparam PHASE_IDLE  = 1'd0;
    localparam PHASE_CRYPT = 1'd1;

    reg phase;
    reg [255:0] key_r;
    reg [31:0] spi_r;
    reg [31:0] seq_r;
    reg [95:0] iv_r;
    reg [7:0] pt_len_r;
    reg [2047:0] pt_r;
    reg [7:0] fbyte [0:292];
    reg [4:0] pt_idx;
    reg [7:0] ct_byte;
    reg feeding_r;
    reg gcm_start;
    reg gcm_pt_valid;
    reg gcm_ct_ready;

    wire gcm_pt_ready;
    wire gcm_ct_valid;
    wire [127:0] gcm_ct_data;
    wire gcm_tag_valid;
    wire [127:0] gcm_tag;
    wire gcm_busy;
    wire gcm_done;

    reg [7:0] ptb [0:255];
    wire [127:0] gcm_pt_data = {
        ptb[pt_idx*16 + 0],  ptb[pt_idx*16 + 1],  ptb[pt_idx*16 + 2],  ptb[pt_idx*16 + 3],
        ptb[pt_idx*16 + 4],  ptb[pt_idx*16 + 5],  ptb[pt_idx*16 + 6],  ptb[pt_idx*16 + 7],
        ptb[pt_idx*16 + 8],  ptb[pt_idx*16 + 9],  ptb[pt_idx*16 + 10], ptb[pt_idx*16 + 11],
        ptb[pt_idx*16 + 12], ptb[pt_idx*16 + 13], ptb[pt_idx*16 + 14], ptb[pt_idx*16 + 15]
    };

    gcm u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(gcm_start), .key(key_r), .nonce(iv_r),
        .aad({spi_r, seq_r, 64'b0}), .aad_len(5'd8),
        .pt_len(pt_len_r),
        .pt_valid(gcm_pt_valid), .pt_ready(gcm_pt_ready), .pt_data(gcm_pt_data),
        .ct_valid(gcm_ct_valid), .ct_ready(gcm_ct_ready), .ct_data(gcm_ct_data),
        .tag_valid(gcm_tag_valid), .tag(gcm_tag),
        .busy(gcm_busy), .done(gcm_done)
    );

    wire [4:0] nct = {1'b0, pt_len_r[7:4]} + {4'd0, |pt_len_r[3:0]};

    wire [7:0] frame_byte [0:292];

    genvar gi;
    generate
        for (gi = 0; gi < 256; gi = gi + 1) begin : gptb
            assign ptb[gi] = pt_r[2047-8*gi -: 8];
        end
        for (gi = 0; gi < 293; gi = gi + 1) begin : gfb
            assign frame_byte[gi] = fbyte[gi];
        end
        for (gi = 0; gi < 293; gi = gi + 1) begin : gfo
            assign frame_out[2343-8*gi -: 8] = fbyte[gi];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            gcm_start <= 1'b0;
            gcm_pt_valid <= 1'b0;
            gcm_ct_ready <= 1'b0;
            pt_idx <= 5'd0;
            ct_byte <= 8'd0;
            feeding_r <= 1'b0;
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
                        ct_byte <= 8'd0;
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
                    if (gcm_ct_valid && ({1'b0, ct_byte} < ({4'd0, nct} * 8'd16)))
                        gcm_ct_ready <= 1'b1;
                    if (gcm_ct_valid && gcm_ct_ready &&
                        ({1'b0, ct_byte} < ({4'd0, nct} * 8'd16))) begin
                        if ({1'b0, ct_byte} + 9'd0 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd20] <= gcm_ct_data[127:120];
                        if ({1'b0, ct_byte} + 9'd1 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd21] <= gcm_ct_data[119:112];
                        if ({1'b0, ct_byte} + 9'd2 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd22] <= gcm_ct_data[111:104];
                        if ({1'b0, ct_byte} + 9'd3 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd23] <= gcm_ct_data[103:96];
                        if ({1'b0, ct_byte} + 9'd4 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd24] <= gcm_ct_data[95:88];
                        if ({1'b0, ct_byte} + 9'd5 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd25] <= gcm_ct_data[87:80];
                        if ({1'b0, ct_byte} + 9'd6 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd26] <= gcm_ct_data[79:72];
                        if ({1'b0, ct_byte} + 9'd7 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd27] <= gcm_ct_data[71:64];
                        if ({1'b0, ct_byte} + 9'd8 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd28] <= gcm_ct_data[63:56];
                        if ({1'b0, ct_byte} + 9'd9 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd29] <= gcm_ct_data[55:48];
                        if ({1'b0, ct_byte} + 9'd10 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd30] <= gcm_ct_data[47:40];
                        if ({1'b0, ct_byte} + 9'd11 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd31] <= gcm_ct_data[39:32];
                        if ({1'b0, ct_byte} + 9'd12 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd32] <= gcm_ct_data[31:24];
                        if ({1'b0, ct_byte} + 9'd13 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd33] <= gcm_ct_data[23:16];
                        if ({1'b0, ct_byte} + 9'd14 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd34] <= gcm_ct_data[15:8];
                        if ({1'b0, ct_byte} + 9'd15 < {1'b0, pt_len_r})
                            fbyte[{1'b0, ct_byte} + 9'd35] <= gcm_ct_data[7:0];
                        ct_byte <= ct_byte + 8'd16;
                    end
                    if (gcm_tag_valid) begin
                        fbyte[0] <= spi_r[31:24];
                        fbyte[1] <= spi_r[23:16];
                        fbyte[2] <= spi_r[15:8];
                        fbyte[3] <= spi_r[7:0];
                        fbyte[4] <= seq_r[31:24];
                        fbyte[5] <= seq_r[23:16];
                        fbyte[6] <= seq_r[15:8];
                        fbyte[7] <= seq_r[7:0];
                        fbyte[8] <= iv_r[95:88];
                        fbyte[9] <= iv_r[87:80];
                        fbyte[10] <= iv_r[79:72];
                        fbyte[11] <= iv_r[71:64];
                        fbyte[12] <= iv_r[63:56];
                        fbyte[13] <= iv_r[55:48];
                        fbyte[14] <= iv_r[47:40];
                        fbyte[15] <= iv_r[39:32];
                        fbyte[16] <= iv_r[31:24];
                        fbyte[17] <= iv_r[23:16];
                        fbyte[18] <= iv_r[15:8];
                        fbyte[19] <= iv_r[7:0];
                        fbyte[{1'b0, pt_len_r} + 9'd20] <= 8'h00;
                        fbyte[{1'b0, pt_len_r} + 9'd21] <= 8'h04;
                        fbyte[{1'b0, pt_len_r} + 9'd22] <= gcm_tag[127:120];
                        fbyte[{1'b0, pt_len_r} + 9'd23] <= gcm_tag[119:112];
                        fbyte[{1'b0, pt_len_r} + 9'd24] <= gcm_tag[111:104];
                        fbyte[{1'b0, pt_len_r} + 9'd25] <= gcm_tag[103:96];
                        fbyte[{1'b0, pt_len_r} + 9'd26] <= gcm_tag[95:88];
                        fbyte[{1'b0, pt_len_r} + 9'd27] <= gcm_tag[87:80];
                        fbyte[{1'b0, pt_len_r} + 9'd28] <= gcm_tag[79:72];
                        fbyte[{1'b0, pt_len_r} + 9'd29] <= gcm_tag[71:64];
                        fbyte[{1'b0, pt_len_r} + 9'd30] <= gcm_tag[63:56];
                        fbyte[{1'b0, pt_len_r} + 9'd31] <= gcm_tag[55:48];
                        fbyte[{1'b0, pt_len_r} + 9'd32] <= gcm_tag[47:40];
                        fbyte[{1'b0, pt_len_r} + 9'd33] <= gcm_tag[39:32];
                        fbyte[{1'b0, pt_len_r} + 9'd34] <= gcm_tag[31:24];
                        fbyte[{1'b0, pt_len_r} + 9'd35] <= gcm_tag[23:16];
                        fbyte[{1'b0, pt_len_r} + 9'd36] <= gcm_tag[15:8];
                        fbyte[{1'b0, pt_len_r} + 9'd37] <= gcm_tag[7:0];
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
