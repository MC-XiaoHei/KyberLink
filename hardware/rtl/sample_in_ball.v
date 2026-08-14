module sample_in_ball (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [383:0] ctilde,
    output reg          busy,
    output reg          done,
    output reg          error,
    output wire [5887:0] coeffs
);
    localparam Q = 23'd8380417;
    localparam TAU = 8'd49;
    localparam JPOS_MAX = 12'd2048;

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;
    localparam PHASE_PROC = 2'd2;
    localparam PHASE_FLUSH = 2'd3;

    reg [22:0] coeffs_arr [0:255];
    integer    ci;

    reg [1:0]    phase;
    reg          shake_start;
    reg [1087:0] blk0;
    reg [1087:0] blk1;
    reg [7:0]    i_idx;
    reg [7:0]    i_cnt;
    reg [11:0]   jpos;

    wire shake_done;
    wire shake_busy;
    wire [1087:0] shake_out;

    shake #(.RATE_BYTES(136)) u_shake (
        .clk(clk), .rst_n(rst_n),
        .start(shake_start),
        .len(12'd48),
        .msg({ctilde, 704'b0}),
        .out_blocks(4'd2),
        .msg_valid(1'b0),
        .need_msg(),
        .busy(shake_busy), .done(shake_done),
        .out(shake_out)
    );

    wire [11:0]  jb_sub = jpos - 12'd136;
    wire [7:0] jb = (jpos < 12'd136) ? blk0[1087 - 8*jpos[7:0] -: 8]
                                     : blk1[1087 - 8*jb_sub[7:0] -: 8];
    wire accept = jb <= i_idx;
    wire [7:0] sbit_off = i_idx - 8'd207;
    wire [2:0] sbyte_off = sbit_off[5:3];
    wire [7:0] sbyte = blk0[1087 - 8*sbyte_off -: 8];
    wire bitv = sbyte[sbit_off[2:0]];
    wire [22:0] cj = bitv ? (Q - 23'd1) : 23'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            shake_start <= 1'b0;
            i_idx <= 8'd207;
            i_cnt <= 8'd0;
            jpos <= 12'd0;
            error <= 1'b0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        i_idx <= 8'd207;
                        i_cnt <= 8'd0;
                        jpos <= 12'd8;
                        error <= 1'b0;
                        for (ci = 0; ci < 256; ci = ci + 1) coeffs_arr[ci] = 23'd0;
                        shake_start <= 1'b1;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    shake_start <= 1'b0;
                    if (shake_done) begin
                        blk0 <= shake_out;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (shake_done) blk1 <= shake_out;
                    if (accept) begin
                        coeffs_arr[i_idx] <= coeffs_arr[jb[7:0]];
                        coeffs_arr[jb[7:0]] <= cj;
                        i_idx <= i_idx + 8'd1;
                        i_cnt <= i_cnt + 8'd1;
                    end
                    jpos <= jpos + 12'd1;
                    if (jpos == JPOS_MAX) begin
                        error <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else if (i_cnt == TAU - 8'd1 && accept) begin
                        if (shake_busy) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            busy <= 1'b0;
                            done <= 1'b1;
                            phase <= PHASE_IDLE;
                        end
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
