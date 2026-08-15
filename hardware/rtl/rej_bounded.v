module rej_bounded (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [511:0]  rho,
    input  wire [15:0]   idx_in,
    output reg           busy,
    output reg           done,
    output reg           error,
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
    reg [7:0]  mem [0:407];

    reg [2:0]  phase;
    reg [8:0]  grp;
    reg [7:0]  idx;
    reg [1:0]  blk_cnt;
    reg [7:0]  retry;
    integer    bb_i;

    assign shk_cfg = {4'd3, 2'd1, 12'd66};

    wire [7:0] bv = mem[grp];
    wire [3:0] lo = bv[3:0];
    wire [3:0] hi = bv[7:4];
    wire lo_ok = lo < 4'd9;
    wire hi_ok = hi < 4'd9;
    wire [22:0] cl = lo_ok ? (lo <= 4'd4 ? {19'd0, (4'd4 - lo)} : Q - {19'd0, (lo - 4'd4)}) : 23'd0;
    wire [22:0] ch = hi_ok ? (hi <= 4'd4 ? {19'd0, (4'd4 - hi)} : Q - {19'd0, (hi - 4'd4)}) : 23'd0;

    wire [8:0] n1 = {1'b0, idx} + (lo_ok ? 9'd1 : 9'd0);
    wire [8:0] n2 = n1 + (hi_ok && n1 < 9'd256 ? 9'd1 : 9'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            idx <= 8'd0;
            grp <= 9'd0;
            blk_cnt <= 2'd0;
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
                        grp <= 9'd0;
                        blk_cnt <= 2'd0;
                        retry <= 8'd0;
                        error <= 1'b0;
                        shk_req <= 1'b1;
                        phase <= PHASE_REQ;
                    end
                end
                PHASE_REQ: begin
                    if (shk_ready) phase <= PHASE_BLK;
                end
                PHASE_BLK: begin
                    shk_blk_valid <= 1'b1;
                    shk_blk_data <= {256'b0, rho, idx_in[7:0], idx_in[15:8], 560'b0};
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
                        for (bb_i = 0; bb_i < 136; bb_i = bb_i + 1)
                            mem[blk_cnt*9'd136 + bb_i] = shk_out_data[1087 - 8*bb_i -: 8];
                        blk_cnt <= blk_cnt + 2'd1;
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (grp >= blk_cnt * 9'd136) begin
                        if (blk_cnt >= 2'd3) begin
                            if (retry == RETRY_MAX) begin
                                shk_req <= 1'b0;
                                error <= 1'b1;
                                busy <= 1'b0;
                                done <= 1'b1;
                                phase <= PHASE_IDLE;
                            end else begin
                                retry <= retry + 8'd1;
                                grp <= 9'd0;
                                blk_cnt <= 2'd0;
                                shk_req <= 1'b0;
                                phase <= PHASE_RETR;
                            end
                        end else begin
                            shk_out_ready <= 1'b1;
                            phase <= PHASE_OUT;
                        end
                    end else begin
                        if (lo_ok) coeffs_arr[idx] <= cl;
                        if (hi_ok && n1 < 9'd256) coeffs_arr[n1[7:0]] <= ch;
                        idx <= n2[7:0];
                        if (n2 >= 9'd256) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            grp <= grp + 9'd1;
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
