module shake256 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  len,
    input  wire [1087:0] msg,
    output reg         busy,
    output reg         done,
    output wire [255:0] out
);
    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_ABSORB = 2'd1;
    localparam PHASE_PAD = 2'd2;
    localparam PHASE_PREP = 2'd3;

    reg [1599:0] state;
    reg [4:0]    round;
    reg [1:0]    phase;
    reg [7:0]    msg_len;

    wire [1599:0] round_out;
    keccak_f1600_round u_round (.state_in(state), .round(round), .state_out(round_out));

    wire [1087:0] msg_rev;
    genvar gi;
    generate
        for (gi = 0; gi < 136; gi = gi + 1) begin: rev
            assign msg_rev[8*gi +: 8] = msg[1080-8*gi +: 8];
        end
    endgenerate

    wire [1599:0] pad_xor = ((1600'h1F) << (8*msg_len)) | (1600'h80 << 1080);

    wire [255:0] out_w;
    genvar oj;
    generate
        for (oj = 0; oj < 32; oj = oj + 1) begin: orev
            assign out_w[255-8*oj -: 8] = state[8*oj +: 8];
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
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        msg_len <= len;
                        busy <= 1'b1;
                        round <= 5'd0;
                        if (len == 8'd0) begin
                            state <= {512'b0, 8'h80, 1072'b0, 8'h1F};
                            phase <= PHASE_PAD;
                        end else begin
                            state <= {512'b0, msg_rev};
                            if (len == 8'd136) begin
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
                    if (msg_len == 8'd136) begin
                        state <= {512'b0, 8'h80, 1072'b0, 8'h1F};
                    end else begin
                        state <= state ^ (1600'h1F << (8*msg_len)) ^ {512'b0, 8'h80, 1072'b0, 8'h00};
                    end
                    phase <= PHASE_PAD;
                end
                PHASE_PAD: begin
                    state <= round_out;
                    if (round == 5'd23) begin
                        phase <= PHASE_IDLE;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        round <= round + 1;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
