module rej_ntt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   s,
    input  wire [7:0]   r,
    output reg          busy,
    output reg          done,
    output reg          error,
    output wire [5887:0] coeffs
);
    localparam Q = 23'd8380417;
    localparam RETRY_MAX = 8'd255;

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;
    localparam PHASE_PROC = 2'd2;
    localparam PHASE_FLUSH = 2'd3;

    reg [22:0] coeffs_arr [0:255];
    reg [7:0]  mem [0:839];

    reg [1:0]    phase;
    reg          shake_start;
    reg [1343:0] blk;
    reg [9:0]    grp;
    reg [7:0]    idx;
    reg [2:0]    blk_cnt;
    reg [7:0]    retry;
    integer      bb_i;

    wire shake_done;
    wire shake_busy;
    wire [1343:0] shake_out;

    shake #(.RATE_BYTES(168)) u_shake (
        .clk(clk), .rst_n(rst_n),
        .start(shake_start),
        .len(12'd34),
        .msg({rho, s, r, 1072'b0}),
        .out_blocks(4'd5),
        .msg_valid(1'b0),
        .need_msg(),
        .busy(shake_busy), .done(shake_done),
        .out(shake_out)
    );

    wire [7:0] b0 = mem[grp];
    wire [7:0] b1 = mem[grp + 10'd1];
    wire [7:0] b2 = mem[grp + 10'd2];
    wire [6:0] b2p = b2[6:0];
    wire [22:0] z = {b2p, b1, b0};

    wire a1 = z < Q;
    wire [8:0] n1 = {1'b0, idx} + (a1 ? 9'd1 : 9'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            shake_start <= 1'b0;
            idx <= 8'd0;
            grp <= 10'd0;
            blk_cnt <= 3'd0;
            retry <= 8'd0;
            error <= 1'b0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        idx <= 8'd0;
                        grp <= 10'd0;
                        blk_cnt <= 3'd0;
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
                        for (bb_i = 0; bb_i < 168; bb_i = bb_i + 1)
                            mem[bb_i] = shake_out[1343 - 8*bb_i -: 8];
                        blk_cnt <= 3'd1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (shake_done && blk_cnt < 3'd5) begin
                        blk <= shake_out;
                        for (bb_i = 0; bb_i < 168; bb_i = bb_i + 1)
                            mem[blk_cnt*9'd168 + bb_i] = shake_out[1343 - 8*bb_i -: 8];
                        blk_cnt <= blk_cnt + 3'd1;
                    end
                    if (a1) coeffs_arr[idx] <= z;
                    idx <= n1[7:0];
                    if (n1 >= 9'd256) begin
                        if (shake_busy) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end
                    end else if (grp >= 10'd838) begin
                        if (retry == RETRY_MAX) begin
                            error <= 1'b1;
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end else begin
                            retry <= retry + 8'd1;
                            grp <= 10'd0;
                            phase <= PHASE_WAIT;
                        end
                    end else begin
                        grp <= grp + 10'd3;
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
            assign coeffs[23*g +: 23] = coeffs_arr[g];
        end
    endgenerate
endmodule
