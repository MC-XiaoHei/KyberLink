module rej_ntt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   s,
    input  wire [7:0]   r,
    output reg          busy,
    output reg          done,
    output reg          error,
    output wire [5887:0] coeffs,

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
    localparam Q = 23'd8380417;
    localparam RETRY_MAX = 8'd255;

    localparam PHASE_IDLE = 3'd0;
    localparam PHASE_REQ  = 3'd1;
    localparam PHASE_BLK  = 3'd2;
    localparam PHASE_BLK2 = 3'd7;
    localparam PHASE_OUT  = 3'd3;
    localparam PHASE_PROC = 3'd4;
    localparam PHASE_FLUSH = 3'd5;
    localparam PHASE_RETR = 3'd6;

    reg [22:0] coeffs_arr [0:255];
    reg [7:0]  mem [0:839];

    reg [2:0]  phase;
    reg [9:0]  grp;
    reg [7:0]  idx;
    reg [2:0]  blk_cnt;
    reg [7:0]  retry;
    integer    bb_i;

    assign shk_cfg = {4'd5, 2'd0, 12'd34};

    wire [7:0] b0 = mem[grp];
    wire [7:0] b1 = mem[grp + 10'd1];
    wire [7:0] b2 = mem[grp + 10'd2];
    wire [6:0] b2p = b2[6:0];
    wire [22:0] z = {b2p, b1, b0};

    wire a1 = z < Q;
    wire [8:0] n1 = {1'b0, idx} + (a1 ? 9'd1 : 9'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            idx <= 8'd0;
            grp <= 10'd0;
            blk_cnt <= 3'd0;
            retry <= 8'd0;
            error <= 1'b0;
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
                        idx <= 8'd0;
                        grp <= 10'd0;
                        blk_cnt <= 3'd0;
                        retry <= 8'd0;
                        error <= 1'b0;
                        shk_req <= 1'b1;
                        phase <= PHASE_REQ;
                    end
                end
                PHASE_REQ: begin
                    if (shk_ready) begin
                        phase <= PHASE_BLK;
                    end
                end
                PHASE_BLK: begin
                    shk_blk_valid <= 1'b1;
                    shk_blk_data <= {rho, s, r, 1072'b0};
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
                        for (bb_i = 0; bb_i < 168; bb_i = bb_i + 1)
                            mem[blk_cnt*9'd168 + bb_i] = shk_out_data[1343 - 8*bb_i -: 8];
                        blk_cnt <= blk_cnt + 3'd1;
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (grp >= blk_cnt * 9'd168) begin
                        if (blk_cnt >= 3'd5) begin
                            if (retry == RETRY_MAX) begin
                                shk_req <= 1'b0;
                                error <= 1'b1;
                                busy <= 1'b0;
                                done <= 1'b1;
                                phase <= PHASE_IDLE;
                            end else begin
                                retry <= retry + 8'd1;
                                grp <= 10'd0;
                                blk_cnt <= 3'd0;
                                shk_req <= 1'b0;
                                phase <= PHASE_RETR;
                            end
                        end else begin
                            shk_out_ready <= 1'b1;
                            phase <= PHASE_OUT;
                        end
                    end else begin
                        if (a1) coeffs_arr[idx] <= z;
                        idx <= n1[7:0];
                        if (n1 >= 9'd256) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            grp <= grp + 10'd3;
                        end
                    end
                end
                PHASE_FLUSH: begin
                    if (shk_out_valid) shk_out_ready <= 1'b1;
                    if (shk_done) begin
                        shk_req <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        phase <= PHASE_IDLE;
                    end
                end
                PHASE_RETR: begin
                    if (shk_done) begin
                        shk_req <= 1'b1;
                        phase <= PHASE_REQ;
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
