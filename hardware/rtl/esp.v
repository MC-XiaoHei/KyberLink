module esp (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [255:0]  key,
    input  wire [31:0]   spi,
    input  wire [31:0]   seq,
    input  wire [95:0]   iv,
    input  wire [1023:0] plaintext_in,
    output reg           busy,
    output reg           done,
    output wire [1327:0] frame_out
);

    localparam PHASE_IDLE = 1'd0;
    localparam PHASE_CRYPT = 1'd1;

    reg phase;
    reg [255:0] key_r;
    reg [31:0] spi_r;
    reg [31:0] seq_r;
    reg [95:0] iv_r;
    reg [1023:0] pt_r;
    reg gcm_start;

    wire gcm_done;
    wire gcm_busy;
    wire [1023:0] gcm_ct;
    wire [127:0] gcm_tag;

    gcm u_gcm (
        .clk(clk), .rst_n(rst_n),
        .start(gcm_start), .key(key_r), .nonce(iv_r),
        .aad({spi_r, seq_r, 64'b0}), .aad_len(5'd8),
        .plaintext_in(pt_r),
        .busy(gcm_busy), .done(gcm_done),
        .ciphertext_out(gcm_ct), .tag(gcm_tag)
    );

    assign frame_out = {spi_r, seq_r, iv_r, gcm_ct, 8'h00, 8'h04, gcm_tag};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            gcm_start <= 1'b0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        key_r <= key;
                        spi_r <= spi;
                        seq_r <= seq;
                        iv_r <= iv;
                        pt_r <= plaintext_in;
                        gcm_start <= 1'b1;
                        busy <= 1'b1;
                        phase <= PHASE_CRYPT;
                    end
                end
                PHASE_CRYPT: begin
                    gcm_start <= 1'b0;
                    if (gcm_done) begin
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
