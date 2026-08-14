module sample_cbd (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   i,
    output reg          busy,
    output reg          done,
    output reg [767:0]  coeffs
);
    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;
    localparam PHASE_PROC = 2'd2;

    reg [1:0]    phase;
    reg          shake_start;
    reg [1087:0] blk;
    reg [4:0]    grp;

    wire shake_done;
    wire [1087:0] shake_out;

    shake #(.RATE_BYTES(136)) u_shake (
        .clk(clk), .rst_n(rst_n),
        .start(shake_start),
        .len(12'd33),
        .msg({rho, i, 824'b0}),
        .out_blocks(4'd1),
        .msg_valid(1'b0),
        .need_msg(),
        .busy(),
        .done(shake_done),
        .out(shake_out)
    );

    wire [7:0] b0 = blk[1087 - 32*grp -: 8];
    wire [7:0] b1 = blk[1079 - 32*grp -: 8];
    wire [7:0] b2 = blk[1071 - 32*grp -: 8];
    wire [7:0] b3 = blk[1063 - 32*grp -: 8];
    wire [31:0] d = {b3, b2, b1, b0};

    wire signed [2:0] c0 = $signed(3'b0 + {2'b0, d[0]} + {2'b0, d[1]}) - $signed(3'b0 + {2'b0, d[2]} + {2'b0, d[3]});
    wire signed [2:0] c1 = $signed(3'b0 + {2'b0, d[4]} + {2'b0, d[5]}) - $signed(3'b0 + {2'b0, d[6]} + {2'b0, d[7]});
    wire signed [2:0] c2 = $signed(3'b0 + {2'b0, d[8]} + {2'b0, d[9]}) - $signed(3'b0 + {2'b0, d[10]} + {2'b0, d[11]});
    wire signed [2:0] c3 = $signed(3'b0 + {2'b0, d[12]} + {2'b0, d[13]}) - $signed(3'b0 + {2'b0, d[14]} + {2'b0, d[15]});
    wire signed [2:0] c4 = $signed(3'b0 + {2'b0, d[16]} + {2'b0, d[17]}) - $signed(3'b0 + {2'b0, d[18]} + {2'b0, d[19]});
    wire signed [2:0] c5 = $signed(3'b0 + {2'b0, d[20]} + {2'b0, d[21]}) - $signed(3'b0 + {2'b0, d[22]} + {2'b0, d[23]});
    wire signed [2:0] c6 = $signed(3'b0 + {2'b0, d[24]} + {2'b0, d[25]}) - $signed(3'b0 + {2'b0, d[26]} + {2'b0, d[27]});
    wire signed [2:0] c7 = $signed(3'b0 + {2'b0, d[28]} + {2'b0, d[29]}) - $signed(3'b0 + {2'b0, d[30]} + {2'b0, d[31]});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            shake_start <= 1'b0;
            grp <= 5'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        grp <= 5'd0;
                        shake_start <= 1'b1;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    shake_start <= 1'b0;
                    if (shake_done) begin
                        blk <= shake_out;
                        grp <= 5'd0;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    coeffs[24*grp +: 24] <= {c7, c6, c5, c4, c3, c2, c1, c0};
                    if (grp == 5'd31) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        grp <= grp + 5'd1;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
