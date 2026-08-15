module sample_cbd3 (
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
    localparam PHASE_IDLE = 4'd0;
    localparam PHASE_REQ  = 4'd1;
    localparam PHASE_BLK  = 4'd2;
    localparam PHASE_BLK2 = 4'd3;
    localparam PHASE_OUT  = 4'd4;
    localparam PHASE_OUT2 = 4'd5;
    localparam PHASE_OUT2W = 4'd6;
    localparam PHASE_PROC = 4'd7;
    localparam PHASE_FLUSH = 4'd8;

    reg [3:0]    phase;
    reg [1087:0] blk0;
    reg [1087:0] blk1;
    reg [5:0]    grp;

    assign shk_cfg = {4'd2, 2'd1, 12'd33};

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
            grp <= 6'd0;
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
                        grp <= 6'd0;
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
                        blk0 <= shk_out_data[1087:0];
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_OUT2;
                    end
                end
                PHASE_OUT2: begin
                    if (!shk_out_valid) phase <= PHASE_OUT2W;
                end
                PHASE_OUT2W: begin
                    if (shk_out_valid) begin
                        blk1 <= shk_out_data[1087:0];
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    coeffs[12*grp +: 12] <= {c3, c2, c1, c0};
                    if (grp == 6'd63) begin
                        phase <= PHASE_FLUSH;
                    end else begin
                        grp <= grp + 6'd1;
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
