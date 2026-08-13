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

    localparam PHASE_IDLE = 1'd0;
    localparam PHASE_CRYPT = 1'd1;

    reg phase;
    reg [255:0] key_r;
    reg [31:0] spi_r;
    reg [31:0] seq_r;
    reg [95:0] iv_r;
    reg [7:0] pt_len_r;
    reg [2047:0] pt_r;
    reg [2343:0] frame_r;
    reg gcm_start;

    wire gcm_done;
    wire gcm_busy;
    wire [2047:0] gcm_ct;
    wire [127:0] gcm_tag;

    gcm u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(gcm_start), .key(key_r), .nonce(iv_r),
        .aad({spi_r, seq_r, 64'b0}), .aad_len(5'd8),
        .pt_len(pt_len_r),
        .plaintext_in(pt_r),
        .busy(gcm_busy), .done(gcm_done),
        .ciphertext_out(gcm_ct), .tag(gcm_tag)
    );

    integer b;
    integer t;

    wire [7:0] frame_byte [0:292];

    genvar gi;
    generate
        for (gi = 0; gi < 293; gi = gi + 1) begin : gfr
            assign frame_byte[gi] = frame_r[2343-8*gi -: 8];
            assign frame_out[2343-8*gi -: 8] = frame_byte[gi];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            gcm_start <= 1'b0;
            frame_r <= 2344'd0;
        end else begin
            done <= 1'b0;
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
                        phase <= PHASE_CRYPT;
                    end
                end
                PHASE_CRYPT: begin
                    gcm_start <= 1'b0;
                    if (gcm_done) begin
                        for (b = 0; b < 4; b = b + 1)
                            frame_r[2343-8*b -: 8] <= spi_r[31-8*b -: 8];
                        for (b = 0; b < 4; b = b + 1)
                            frame_r[2343-32-8*b -: 8] <= seq_r[31-8*b -: 8];
                        for (b = 0; b < 12; b = b + 1)
                            frame_r[2343-64-8*b -: 8] <= iv_r[95-8*b -: 8];
                        for (b = 0; b < 255; b = b + 1)
                            frame_r[2343-8*(20+b) -: 8] <= (b < {24'd0, pt_len_r}) ? gcm_ct[2047-8*b -: 8] : 8'd0;
                        frame_r[2343-8*(20+{24'd0, pt_len_r}) -: 8] <= 8'h00;
                        frame_r[2343-8*(21+{24'd0, pt_len_r}) -: 8] <= 8'h04;
                        for (t = 0; t < 16; t = t + 1)
                            frame_r[2343-8*(22+{24'd0, pt_len_r}+t) -: 8] <= gcm_tag[127-8*t -: 8];
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
