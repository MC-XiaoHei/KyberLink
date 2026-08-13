module sample_cbd3 (
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
    localparam PHASE_WAIT2 = 2'd2;
    localparam PHASE_PROC = 2'd3;

    reg [1:0]    phase;
    reg          shake_start;
    reg [1087:0] blk0;
    reg [1087:0] blk1;
    reg [5:0]    grp;

    wire shake_done;
    wire [1087:0] shake_out;

    shake #(.RATE_BYTES(136)) u_shake (
        .clk(clk), .rst_n(rst_n),
        .start(shake_start),
        .len(12'd33),
        .msg({rho, i, 824'b0}),
        .out_blocks(4'd2),
        .msg_valid(1'b0),
        .need_msg(),
        .busy(),
        .done(shake_done),
        .out(shake_out)
    );

    wire [2175:0] stream;
    genvar gi;
    generate
        for (gi = 0; gi < 136; gi = gi + 1) begin: sa
            assign stream[2175 - 8*gi -: 8] = blk0[1087 - 8*gi -: 8];
        end
        for (gi = 136; gi < 192; gi = gi + 1) begin: sb
            assign stream[2175 - 8*gi -: 8] = blk1[1087 - 8*(gi-136) -: 8];
        end
    endgenerate

    wire [7:0] base = {grp, 1'b0} + {2'b0, grp};
    wire [7:0] sb0 = stream[2175 - 8*base -: 8];
    wire [7:0] sb1 = stream[2175 - 8*base - 8 -: 8];
    wire [7:0] sb2 = stream[2175 - 8*base - 16 -: 8];
    wire [23:0] t24 = {sb2, sb1, sb0};

    wire signed [2:0] c0 = $signed(3'b0 + {2'b0,t24[0]} + {2'b0,t24[1]} + {2'b0,t24[2]}) - $signed(3'b0 + {2'b0,t24[3]} + {2'b0,t24[4]} + {2'b0,t24[5]});
    wire signed [2:0] c1 = $signed(3'b0 + {2'b0,t24[6]} + {2'b0,t24[7]} + {2'b0,t24[8]}) - $signed(3'b0 + {2'b0,t24[9]} + {2'b0,t24[10]} + {2'b0,t24[11]});
    wire signed [2:0] c2 = $signed(3'b0 + {2'b0,t24[12]} + {2'b0,t24[13]} + {2'b0,t24[14]}) - $signed(3'b0 + {2'b0,t24[15]} + {2'b0,t24[16]} + {2'b0,t24[17]});
    wire signed [2:0] c3 = $signed(3'b0 + {2'b0,t24[18]} + {2'b0,t24[19]} + {2'b0,t24[20]}) - $signed(3'b0 + {2'b0,t24[21]} + {2'b0,t24[22]} + {2'b0,t24[23]});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            shake_start <= 1'b0;
            grp <= 6'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        grp <= 6'd0;
                        shake_start <= 1'b1;
                        phase <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    shake_start <= 1'b0;
                    if (shake_done) begin
                        blk0 <= shake_out;
                        phase <= PHASE_WAIT2;
                    end
                end
                PHASE_WAIT2: begin
                    if (shake_done) begin
                        blk1 <= shake_out;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    coeffs[12*grp +: 12] <= {c3, c2, c1, c0};
                    if (grp == 6'd63) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end else begin
                        grp <= grp + 6'd1;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
