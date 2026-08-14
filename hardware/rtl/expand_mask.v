module expand_mask (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] rho,
    input  wire [15:0]  mu,
    output reg          busy,
    output reg          done,
    output wire [5887:0] coeffs
);
    localparam Q = 23'd8380417;
    localparam GAMMA1 = 20'd524288;

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;
    localparam PHASE_PROC = 2'd2;
    localparam PHASE_FLUSH = 2'd3;

    reg [22:0] coeffs_arr [0:255];
    reg [7:0]  mem [0:639];

    reg [1:0]    phase;
    reg          shake_start;
    reg [1087:0] blk;
    reg [8:0]    p;
    reg [8:0]    blk_cnt;
    integer      bb_i;

    wire shake_done;
    wire shake_busy;
    wire [1087:0] shake_out;

    shake #(.RATE_BYTES(136)) u_shake (
        .clk(clk), .rst_n(rst_n),
        .start(shake_start),
        .len(12'd66),
        .msg({rho, mu[7:0], mu[15:8], 560'b0}),
        .out_blocks(4'd5),
        .msg_valid(1'b0),
        .need_msg(),
        .busy(shake_busy), .done(shake_done),
        .out(shake_out)
    );

    wire [12:0] base = 13'd20 * {4'd0, p};
    wire [2:0] bo = base[2:0];
    wire [9:0] bi = base[12:3];
    wire [7:0] mv0 = mem[bi];
    wire [7:0] mv1 = mem[bi + 10'd1];
    wire [7:0] mv2 = mem[bi + 10'd2];
    wire [19:0] v = ({12'd0, mv0} >> bo)
                  | ({12'd0, mv1} << (8'd8 - {5'd0, bo}))
                  | ({12'd0, mv2} << (8'd16 - {5'd0, bo}));
    wire [23:0] sumv = {4'd0, GAMMA1} + {1'b0, Q} - {4'd0, v};
    wire [22:0] yv = (sumv >= {1'b0, Q}) ? (sumv[22:0] - Q) : sumv[22:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            shake_start <= 1'b0;
            p <= 9'd0;
            blk_cnt <= 9'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        p <= 9'd0;
                        blk_cnt <= 9'd0;
                        shake_start <= 1'b1;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    shake_start <= 1'b0;
                    if (shake_done) begin
                        for (bb_i = 0; bb_i < 136; bb_i = bb_i + 1)
                            mem[bb_i] = shake_out[1087 - 8*bb_i -: 8];
                        blk_cnt <= 9'd1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (shake_done && blk_cnt < 9'd5) begin
                        for (bb_i = 0; bb_i < 136; bb_i = bb_i + 1)
                            mem[blk_cnt*9'd136 + bb_i] = shake_out[1087 - 8*bb_i -: 8];
                        blk_cnt <= blk_cnt + 9'd1;
                    end
                    coeffs_arr[p[7:0]] <= yv;
                    if (p == 9'd255) begin
                        if (shake_busy) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end
                    end else begin
                        p <= p + 9'd1;
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
