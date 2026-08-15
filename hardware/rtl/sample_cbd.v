module sample_cbd (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   i,
    output reg          busy,
    output reg          done,
    output reg [767:0]  coeffs,

    output reg          shk_req,
    output wire [17:0]  shk_cfg,
    input  wire         shk_ready,
    input  wire         shk_done,
    output reg          shk_blk_valid,
    input  wire         shk_blk_ready,
    output reg  [1343:0] shk_blk_data,
    input  wire         shk_out_valid,
    output reg          shk_out_ready,
    input  wire  [1343:0] shk_out_data
);
    localparam PHASE_IDLE = 3'd0;
    localparam PHASE_REQ  = 3'd1;
    localparam PHASE_BLK  = 3'd2;
    localparam PHASE_BLK2 = 3'd7;
    localparam PHASE_OUT  = 3'd3;
    localparam PHASE_PROC = 3'd4;
    localparam PHASE_FLUSH = 3'd5;

    reg [2:0]  phase;
    reg [1087:0] blk;
    reg [4:0]  grp;

    assign shk_cfg = {4'd1, 2'd1, 12'd33};

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
            grp <= 5'd0;
            shk_req <= 1'b0;
            shk_blk_valid <= 1'b0;
            shk_out_ready <= 1'b0;
            shk_blk_data <= 1344'b0;
        end else begin
            done <= 1'b0;
            shk_out_ready <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        grp <= 5'd0;
                        shk_req <= 1'b1;
                        phase <= PHASE_REQ;
                    end
                end
                PHASE_REQ: begin
                    if (shk_ready) phase <= PHASE_BLK;
                end
                PHASE_BLK: begin
                    shk_blk_valid <= 1'b1;
                    shk_blk_data <= {256'b0, rho, i, 824'b0};
                    phase <= PHASE_BLK2;
                end
                PHASE_BLK2: begin
                    if (shk_blk_ready) begin
                        shk_blk_valid <= 1'b0;
                        phase <= PHASE_OUT;
                    end
                end
                PHASE_OUT: begin
                    if (shk_out_valid) begin
                        blk <= shk_out_data[1087:0];
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    coeffs[24*grp +: 24] <= {c7, c6, c5, c4, c3, c2, c1, c0};
                    if (grp == 5'd31) begin
                        phase <= PHASE_FLUSH;
                    end else begin
                        grp <= grp + 5'd1;
                    end
                end
                PHASE_FLUSH: begin
                    if (shk_done) begin
                        shk_req <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
