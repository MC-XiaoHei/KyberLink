module shake #(parameter RATE_BYTES = 136) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  len,
    input  wire [3:0]  out_blocks,
    input  wire [RATE_BYTES*8-1:0] msg,
    output reg         busy,
    output reg         done,
    output wire [RATE_BYTES*8-1:0] out
);
    localparam PHASE_IDLE = 3'd0;
    localparam PHASE_ABSORB = 3'd1;
    localparam PHASE_PREP = 3'd2;
    localparam PHASE_PAD = 3'd3;
    localparam PHASE_PADX = 3'd4;
    localparam PHASE_SQUEEZE = 3'd5;

    localparam HIGH_ZERO = 1600 - RATE_BYTES*8;

    reg [1599:0] state;
    reg [4:0]    round;
    reg [2:0]    phase;
    reg [7:0]    msg_len;
    reg [3:0]    blk_cnt;
    reg [3:0]    blk_total;

    wire [1599:0] round_out;
    keccak_f1600_round u_round (.state_in(state), .round(round), .state_out(round_out));

    wire [RATE_BYTES*8-1:0] msg_rev;
    genvar gi;
    generate
        for (gi = 0; gi < RATE_BYTES; gi = gi + 1) begin: rev
            assign msg_rev[8*gi +: 8] = msg[RATE_BYTES*8-8-8*gi +: 8];
        end
    endgenerate

    wire [1599:0] pad_const = {{HIGH_ZERO{1'b0}}, 8'h80, {(RATE_BYTES*8-16){1'b0}}, 8'h1F};
    wire [1599:0] pad_xor = ((1600'h1F) << (8*msg_len)) ^ (1600'h80 << (8*(RATE_BYTES-1)));

    wire [RATE_BYTES*8-1:0] out_w;
    genvar oj;
    generate
        for (oj = 0; oj < RATE_BYTES; oj = oj + 1) begin: orev
            assign out_w[RATE_BYTES*8-8-8*oj +: 8] = state[8*oj +: 8];
        end
    endgenerate
    assign out = out_w;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 1600'b0;
            round <= 5'd0;
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            blk_cnt <= 4'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        msg_len <= len;
                        blk_total <= out_blocks;
                        blk_cnt <= 4'd1;
                        busy <= 1'b1;
                        round <= 5'd0;
                        if (len == 8'd0) begin
                            state <= pad_const;
                            phase <= PHASE_PAD;
                        end else begin
                            state <= {{HIGH_ZERO{1'b0}}, msg_rev};
                            if (len == RATE_BYTES[7:0]) begin
                                phase <= PHASE_ABSORB;
                            end else begin
                                phase <= PHASE_PREP;
                            end
                        end
                    end
                end
                PHASE_ABSORB: begin
                    state <= round_out;
                    if (round == 5'd23) begin
                        round <= 5'd0;
                        phase <= PHASE_PREP;
                    end else begin
                        round <= round + 1;
                    end
                end
                PHASE_PREP: begin
                    if (msg_len == RATE_BYTES[7:0]) begin
                        state <= pad_const;
                    end else begin
                        state <= state ^ pad_xor;
                    end
                    phase <= PHASE_PAD;
                end
                PHASE_PAD, PHASE_SQUEEZE: begin
                    state <= round_out;
                    if (round == 5'd23) begin
                        round <= 5'd0;
                        done <= 1'b1;
                        phase <= PHASE_PADX;
                    end else begin
                        round <= round + 1;
                    end
                end
                PHASE_PADX: begin
                    if (blk_cnt >= blk_total) begin
                        phase <= PHASE_IDLE;
                        busy <= 1'b0;
                    end else begin
                        blk_cnt <= blk_cnt + 1;
                        phase <= PHASE_SQUEEZE;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
