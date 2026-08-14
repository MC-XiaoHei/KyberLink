module matmul_dsa (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [176639:0] a_in,
    input  wire [29439:0]  b_in,
    output reg           busy,
    output reg           done,
    output wire [35327:0] c_out
);
    localparam Q = 23'd8380417;
    localparam MULT = 26'd33587228;
    localparam PHASE_IDLE = 1'b0;
    localparam PHASE_RUN = 1'b1;

    reg phase;
    reg [10:0] p;

    reg [22:0] a_arr [0:29][0:255];
    reg [22:0] b_arr [0:4][0:255];
    reg [22:0] c_arr [0:1535];

    wire [2:0] i_cnt = p[10:8];
    wire [7:0] k_cnt = p[7:0];

    wire [4:0] i_cnt5 = {2'b0, i_cnt};
    wire [6:0] ai0 = {i_cnt5, 2'b0} + {2'b0, i_cnt5};
    wire [6:0] ai1 = ai0 + 7'd1;
    wire [6:0] ai2 = ai0 + 7'd2;
    wire [6:0] ai3 = ai0 + 7'd3;
    wire [6:0] ai4 = ai0 + 7'd4;
    wire [22:0] av0 = a_arr[ai0[4:0]][k_cnt];
    wire [22:0] av1 = a_arr[ai1[4:0]][k_cnt];
    wire [22:0] av2 = a_arr[ai2[4:0]][k_cnt];
    wire [22:0] av3 = a_arr[ai3[4:0]][k_cnt];
    wire [22:0] av4 = a_arr[ai4[4:0]][k_cnt];
    wire [22:0] bv0 = b_arr[3'd0][k_cnt];
    wire [22:0] bv1 = b_arr[3'd1][k_cnt];
    wire [22:0] bv2 = b_arr[3'd2][k_cnt];
    wire [22:0] bv3 = b_arr[3'd3][k_cnt];
    wire [22:0] bv4 = b_arr[3'd4][k_cnt];

    wire [45:0] pr0 = av0 * bv0;
    wire [45:0] pr1 = av1 * bv1;
    wire [45:0] pr2 = av2 * bv2;
    wire [45:0] pr3 = av3 * bv3;
    wire [45:0] pr4 = av4 * bv4;
    wire [48:0] ssum = {3'b0, pr0} + {3'b0, pr1} + {3'b0, pr2} + {3'b0, pr3} + {3'b0, pr4};

    function [22:0] barrett23(input [48:0] x);
        reg [74:0] mx;
        reg [49:0] mq;
        reg [49:0] rr;
        reg [49:0] rr1;
        begin
            mx = x * MULT;
            mq = mx[74:48] * Q;
            rr = x - mq;
            rr1 = (rr >= {27'd0, Q}) ? (rr - {27'd0, Q}) : rr;
            rr1 = (rr1 >= {27'd0, Q}) ? (rr1 - {27'd0, Q}) : rr1;
            barrett23 = rr1[22:0];
        end
    endfunction

    wire [22:0] c_res = barrett23(ssum);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            p <= 11'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        p <= 11'd0;
                        busy <= 1'b1;
                        phase <= PHASE_RUN;
                    end
                end
                PHASE_RUN: begin
                    c_arr[p] <= c_res;
                    if (p == 11'd1535) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        p <= p + 11'd1;
                    end
                end
            endcase
        end
    end

    integer jl;
    integer kl;
    always @(posedge clk or negedge rst_n) begin
        if (start && (phase == PHASE_IDLE)) begin
            for (jl = 0; jl < 30; jl = jl + 1) begin
                for (kl = 0; kl < 256; kl = kl + 1) begin
                    a_arr[jl][kl] = a_in[23 * (256 * jl + kl) +: 23];
                end
            end
            for (jl = 0; jl < 5; jl = jl + 1) begin
                for (kl = 0; kl < 256; kl = kl + 1) begin
                    b_arr[jl][kl] = b_in[23 * (256 * jl + kl) +: 23];
                end
            end
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < 1536; gi = gi + 1) begin : g_co
            assign c_out[23 * gi +: 23] = c_arr[gi];
        end
    endgenerate
endmodule
