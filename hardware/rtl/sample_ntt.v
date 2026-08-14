module sample_ntt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [255:0] rho,
    input  wire [7:0]  i,
    input  wire [7:0]  j,
    output reg         busy,
    output reg         done,
    output reg         error,
    output wire [3071:0] coeffs
);
    localparam Q = 12'd3329;
    localparam RETRY_MAX = 8'd255;

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;
    localparam PHASE_PROC = 2'd2;
    localparam PHASE_FLUSH = 2'd3;

    reg [11:0] coeffs_arr [0:255];

    reg [1:0]    phase;
    reg          shake_start;
    reg [1343:0] blk;
    reg [1343:0] blk_next;
    reg [8:0]    grp;
    reg [7:0]    idx;
    reg          has_next;
    reg [7:0]    retry;

    wire shake_done;
    wire shake_busy;
    wire [1343:0] shake_out;

    shake #(.RATE_BYTES(168)) u_shake (
        .clk(clk), .rst_n(rst_n),
        .start(shake_start),
        .len(12'd34),
        .msg({rho, i, j, 1072'b0}),
        .out_blocks(4'd5),
        .msg_valid(1'b0),
        .need_msg(),
        .busy(shake_busy), .done(shake_done),
        .out(shake_out)
    );

    wire [7:0] b0a = blk[1343 - 24*grp -: 8];
    wire [7:0] b1a = blk[1335 - 24*grp -: 8];
    wire [7:0] b2a = blk[1327 - 24*grp -: 8];
    wire [7:0] b0b = blk[1319 - 24*grp -: 8];
    wire [7:0] b1b = blk[1311 - 24*grp -: 8];
    wire [7:0] b2b = blk[1303 - 24*grp -: 8];
    wire [7:0] b0c = blk[1295 - 24*grp -: 8];
    wire [7:0] b1c = blk[1287 - 24*grp -: 8];
    wire [7:0] b2c = blk[1279 - 24*grp -: 8];

    wire [11:0] d1a = {b1a[3:0], b0a};
    wire [11:0] d2a = {b2a, b1a[7:4]};
    wire [11:0] d1b = {b1b[3:0], b0b};
    wire [11:0] d2b = {b2b, b1b[7:4]};
    wire [11:0] d1c = {b1c[3:0], b0c};
    wire [11:0] d2c = {b2c, b1c[7:4]};

    wire a1a = d1a < Q;
    wire [8:0] n1a = {1'b0, idx} + (a1a ? 9'd1 : 9'd0);
    wire a2a = d2a < Q && n1a < 9'd256;
    wire [8:0] n2a = n1a + (a2a ? 9'd1 : 9'd0);
    wire a1b = d1b < Q && n2a < 9'd256;
    wire [8:0] n1b = n2a + (a1b ? 9'd1 : 9'd0);
    wire a2b = d2b < Q && n1b < 9'd256;
    wire [8:0] n2b = n1b + (a2b ? 9'd1 : 9'd0);
    wire c_ok = (grp != 9'd54);
    wire a1c = c_ok && d1c < Q && n2b < 9'd256;
    wire [8:0] n1c = n2b + (a1c ? 9'd1 : 9'd0);
    wire a2c = c_ok && d2c < Q && n1c < 9'd256;
    wire [8:0] n2c = n1c + (a2c ? 9'd1 : 9'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            shake_start <= 1'b0;
            idx <= 8'd0;
            grp <= 9'd0;
            has_next <= 1'b0;
            retry <= 8'd0;
            error <= 1'b0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        idx <= 8'd0;
                        grp <= 9'd0;
                        has_next <= 1'b0;
                        retry <= 8'd0;
                        error <= 1'b0;
                        shake_start <= 1'b1;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    shake_start <= 1'b0;
                    if (shake_done) begin
                        blk <= shake_out;
                        grp <= 9'd0;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (shake_done) begin
                        blk_next <= shake_out;
                        has_next <= 1'b1;
                    end
                    if (a1a) coeffs_arr[idx[7:0]] <= d1a;
                    if (a2a) coeffs_arr[n1a[7:0]] <= d2a;
                    if (a1b) coeffs_arr[n2a[7:0]] <= d1b;
                    if (a2b) coeffs_arr[n1b[7:0]] <= d2b;
                    if (a1c) coeffs_arr[n2b[7:0]] <= d1c;
                    if (a2c) coeffs_arr[n1c[7:0]] <= d2c;
                    idx <= n2c[7:0];
                    if (n2c >= 9'd256) begin
                        if (shake_busy) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end
                    end else if (grp == 9'd54) begin
                        if (has_next) begin
                            blk <= blk_next;
                            has_next <= 1'b0;
                            grp <= 9'd0;
                        end else begin
                            if (retry == RETRY_MAX) begin
                                error <= 1'b1;
                                busy <= 1'b0;
                                done <= 1'b1;
                                phase <= PHASE_IDLE;
                            end else begin
                                retry <= retry + 8'd1;
                                grp <= 9'd0;
                                phase <= PHASE_WAIT;
                            end
                        end
                    end else begin
                        grp <= grp + 9'd3;
                    end
                end
                PHASE_FLUSH: begin
                    if (!shake_busy) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    genvar g;
    generate
        for (g = 0; g < 256; g = g + 1) begin : out_map
            assign coeffs[12*g +: 12] = coeffs_arr[g];
        end
    endgenerate
endmodule
