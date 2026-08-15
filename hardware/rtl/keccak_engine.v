module keccak_engine #(
    parameter N_REQ    = 8,
    parameter MAX_RATE = 168
) (
    input  wire clk,
    input  wire rst_n,

    input  wire [N_REQ-1:0]    req_valid,
    output wire [N_REQ-1:0]    req_ready,
    output wire [N_REQ-1:0]    req_done,
    input  wire [N_REQ*18-1:0] req_cfg,

    input  wire                blk_valid,
    output wire                blk_ready,
    input  wire [MAX_RATE*8-1:0] blk_data,

    output reg                 out_valid,
    input  wire                out_ready,
    output wire [MAX_RATE*8-1:0] out_data
);

    localparam PHASE_IDLE = 3'd0;
    localparam PHASE_WAIT = 3'd1;
    localparam PHASE_ABS  = 3'd2;
    localparam PHASE_PREP = 3'd3;
    localparam PHASE_PERM = 3'd4;
    localparam PHASE_OUTW = 3'd5;
    localparam PHASE_SQZ  = 3'd6;

    localparam OWNER_W = (N_REQ <= 2) ? 1 : $clog2(N_REQ);

    reg [1599:0] state;
    reg [4:0]    round;
    reg [2:0]    phase;
    reg [OWNER_W-1:0] owner;
    reg [1:0]    mode_r;
    reg [3:0]    blk_total;
    reg [11:0]   msg_len;
    reg [11:0]   rem;
    reg [3:0]    blk_cnt;
    reg          last_full;
    reg          first_blk;
    reg [N_REQ-1:0] ready_r;
    reg [N_REQ-1:0] done_r;

    wire [1599:0] round_out;
    keccak_f1600_round u_round (.state_in(state), .round(round), .state_out(round_out));

    reg [7:0] rate_w;
    reg [7:0] dom_w;
    always @(*) begin
        case (mode_r)
            2'd0: begin rate_w = 8'd168; dom_w = 8'h1F; end
            2'd1: begin rate_w = 8'd136; dom_w = 8'h1F; end
            2'd2: begin rate_w = 8'd136; dom_w = 8'h06; end
            default: begin rate_w = 8'd72; dom_w = 8'h06; end
        endcase
    end

    reg [11:0] mod_r;
    reg [1599:0] pad_const;
    reg [1599:0] pad_xor;
    integer pi;
    always @(*) begin
        mod_r = msg_len;
        for (pi = 0; pi < 12; pi = pi + 1) begin
            if (mod_r >= {4'd0, rate_w}) mod_r = mod_r - {4'd0, rate_w};
        end
        pad_const = (1600'h80 << (8*rate_w - 8)) | {1592'b0, dom_w};
        pad_xor = ({1592'b0, dom_w} << (8*mod_r)) ^ (1600'h80 << (8*rate_w - 8));
    end

    reg [MAX_RATE*8-1:0] blk_rev;
    reg [MAX_RATE*8-1:0] out_w;
    integer bi;
    always @(*) begin
        for (bi = 0; bi < MAX_RATE; bi = bi + 1) begin
            if (bi < rate_w) begin
                blk_rev[8*bi +: 8] = blk_data[8*rate_w - 8 - 8*bi +: 8];
                out_w[8*bi +: 8] = state[8*rate_w - 8 - 8*bi +: 8];
            end else begin
                blk_rev[8*bi +: 8] = 8'b0;
                out_w[8*bi +: 8] = 8'b0;
            end
        end
    end

    assign out_data = out_w;
    assign blk_ready = (phase == PHASE_WAIT);

    wire [N_REQ-1:0] grant;
    reg [N_REQ-1:0] grant_r;
    reg found_w;
    integer gi2;
    always @(*) begin
        grant_r = {N_REQ{1'b0}};
        found_w = 1'b0;
        for (gi2 = 0; gi2 < N_REQ; gi2 = gi2 + 1) begin
            grant_r[gi2] = req_valid[gi2] && !found_w && (phase == PHASE_IDLE) && (done_r[gi2] == 1'b0);
            found_w = found_w | grant_r[gi2];
        end
    end
    assign grant = grant_r;

    assign req_ready = ready_r;
    assign req_done  = done_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 1600'b0;
            round <= 5'd0;
            phase <= PHASE_IDLE;
                                owner <= {OWNER_W{1'b0}};
            mode_r <= 2'd0;
            blk_total <= 4'd0;
            msg_len <= 12'd0;
            rem <= 12'd0;
            blk_cnt <= 4'd0;
            last_full <= 1'b0;
            first_blk <= 1'b0;
            ready_r <= {N_REQ{1'b0}};
            done_r <= {N_REQ{1'b0}};
            out_valid <= 1'b0;
        end else begin
            case (phase)
                PHASE_IDLE: begin
                    if (grant != {N_REQ{1'b0}}) begin
                        for (gi2 = 0; gi2 < N_REQ; gi2 = gi2 + 1) begin
                            if (grant[gi2]) begin
                                owner <= gi2[OWNER_W-1:0];
                                {blk_total, mode_r, msg_len} <= req_cfg[18*gi2 +: 18];
                                ready_r[gi2] <= 1'b1;
                            end
                        end
                        first_blk <= 1'b1;
                        blk_cnt <= 4'd0;
                        last_full <= 1'b0;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    if (msg_len == 12'd0) begin
                        phase <= PHASE_PREP;
                    end else if (blk_valid) begin
                        if (first_blk) begin
                            state <= {256'b0, blk_rev};
                            first_blk <= 1'b0;
                            if (msg_len > {4'd0, rate_w}) begin
                                rem <= msg_len - {4'd0, rate_w};
                                phase <= PHASE_ABS;
                            end else if (msg_len == {4'd0, rate_w}) begin
                                last_full <= 1'b1;
                                phase <= PHASE_ABS;
                            end else begin
                                phase <= PHASE_PREP;
                            end
                        end else begin
                            state <= state ^ {256'b0, blk_rev};
                            if (rem > {4'd0, rate_w}) begin
                                rem <= rem - {4'd0, rate_w};
                                phase <= PHASE_ABS;
                            end else if (rem == {4'd0, rate_w}) begin
                                last_full <= 1'b1;
                                phase <= PHASE_ABS;
                            end else begin
                                phase <= PHASE_PREP;
                            end
                        end
                    end
                end
                PHASE_ABS: begin
                    state <= round_out;
                    if (round == 5'd23) begin
                        round <= 5'd0;
                        if (rem > 12'd0) begin
                            phase <= PHASE_WAIT;
                        end else begin
                            phase <= PHASE_PREP;
                        end
                    end else begin
                        round <= round + 5'd1;
                    end
                end
                PHASE_PREP: begin
                    if (last_full) begin
                        state <= state ^ pad_const;
                    end else begin
                        state <= state ^ pad_xor;
                    end
                    last_full <= 1'b0;
                    blk_cnt <= 4'd1;
                    phase <= PHASE_PERM;
                end
                PHASE_PERM, PHASE_SQZ: begin
                    state <= round_out;
                    if (round == 5'd23) begin
                        round <= 5'd0;
                        out_valid <= 1'b1;
                        phase <= PHASE_OUTW;
                    end else begin
                        round <= round + 5'd1;
                    end
                end
                PHASE_OUTW: begin
                    if (out_ready) begin
                        out_valid <= 1'b0;
                        if (blk_cnt >= blk_total) begin
                            done_r[owner] <= 1'b1;
                        end else begin
                            blk_cnt <= blk_cnt + 4'd1;
                            phase <= PHASE_SQZ;
                        end
                    end
                    if (done_r[owner]) begin
                        if (!req_valid[owner]) begin
                            ready_r[owner] <= 1'b0;
                            done_r[owner] <= 1'b0;
                            owner <= {OWNER_W{1'b0}};
                            phase <= PHASE_IDLE;
                        end
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

    endmodule
