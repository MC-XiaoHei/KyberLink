module rej_bounded (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [511:0]  rho,
    input  wire [15:0]   idx_in,
    output reg           busy,
    output reg           done,
    output wire [5887:0] coeffs
);
    localparam Q = 23'd8380417;

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;
    localparam PHASE_PROC = 2'd2;
    localparam PHASE_FLUSH = 2'd3;

    reg [22:0] coeffs_arr [0:255];
    reg [7:0]  mem [0:407];

    reg [1:0]    phase;
    reg          shake_start;
    reg [1087:0] blk;
    reg [8:0]    grp;
    reg [7:0]    idx;
    reg [1:0]    blk_cnt;
    integer      bb_i;

    wire shake_done;
    wire shake_busy;
    wire [1087:0] shake_out;

    shake #(.RATE_BYTES(136)) u_shake (
        .clk(clk), .rst_n(rst_n),
        .start(shake_start),
        .len(12'd66),
        .msg({rho, idx_in[7:0], idx_in[15:8], 560'b0}),
        .out_blocks(4'd3),
        .msg_valid(1'b0),
        .need_msg(),
        .busy(shake_busy), .done(shake_done),
        .out(shake_out)
    );

    wire [7:0] bv = mem[grp];
    wire [3:0] lo = bv[3:0];
    wire [3:0] hi = bv[7:4];
    wire lo_ok = lo < 4'd9;
    wire hi_ok = hi < 4'd9;
    wire [22:0] cl = lo_ok ? (lo <= 4'd4 ? {19'd0, (4'd4 - lo)} : Q - {19'd0, (lo - 4'd4)}) : 23'd0;
    wire [22:0] ch = hi_ok ? (hi <= 4'd4 ? {19'd0, (4'd4 - hi)} : Q - {19'd0, (hi - 4'd4)}) : 23'd0;

    wire [8:0] n1 = {1'b0, idx} + (lo_ok ? 9'd1 : 9'd0);
    wire [8:0] n2 = n1 + (hi_ok && n1 < 9'd256 ? 9'd1 : 9'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            shake_start <= 1'b0;
            idx <= 8'd0;
            grp <= 9'd0;
            blk_cnt <= 2'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        idx <= 8'd0;
                        grp <= 9'd0;
                        blk_cnt <= 2'd0;
                        shake_start <= 1'b1;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    shake_start <= 1'b0;
                    if (shake_done) begin
                        blk <= shake_out;
                        for (bb_i = 0; bb_i < 136; bb_i = bb_i + 1)
                            mem[bb_i] = shake_out[1087 - 8*bb_i -: 8];
                        blk_cnt <= 2'd1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (shake_done && blk_cnt < 2'd3) begin
                        blk <= shake_out;
                        for (bb_i = 0; bb_i < 136; bb_i = bb_i + 1)
                            mem[blk_cnt*9'd136 + bb_i] = shake_out[1087 - 8*bb_i -: 8];
                        blk_cnt <= blk_cnt + 2'd1;
                    end
                    if (lo_ok) coeffs_arr[idx] <= cl;
                    if (hi_ok && n1 < 9'd256) coeffs_arr[n1[7:0]] <= ch;
                    idx <= n2[7:0];
                    if (n2 >= 9'd256) begin
                        if (shake_busy) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end
                    end else if (grp == 9'd407) begin
                        grp <= 9'd0;
                        phase <= PHASE_WAIT;
                    end else begin
                        grp <= grp + 9'd1;
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
