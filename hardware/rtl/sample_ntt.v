module sample_ntt (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] rho,
    input  wire [7:0]   i,
    input  wire [7:0]   j,
    output reg          busy,
    output reg          done,
    output reg          error,
    output wire [3071:0] coeffs,

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
    localparam Q = 12'd3329;
    localparam RETRY_MAX = 8'd255;

    localparam PHASE_IDLE = 3'd0;
    localparam PHASE_REQ  = 3'd1;
    localparam PHASE_BLK  = 3'd2;
    localparam PHASE_BLK2 = 3'd3;
    localparam PHASE_OUT  = 3'd4;
    localparam PHASE_PROC = 3'd5;
    localparam PHASE_FLUSH = 3'd6;
    localparam PHASE_RETR = 3'd7;

    reg [11:0] coeffs_arr [0:255];
    reg [7:0]  mem [0:839];

    reg [2:0]  phase;
    reg [11:0] grp;
    reg [7:0]  idx;
    reg [3:0]  blk_cnt;
    reg [7:0]  retry;
    integer    bb_i;

    assign shk_cfg = {4'd5, 2'd0, 12'd34};

    wire [11:0] blk_base = ({8'd0, blk_cnt} - 12'd1) * 12'd168;

    wire [7:0] b0a = mem[blk_base + 3*grp];
    wire [7:0] b1a = mem[blk_base + 3*grp + 12'd1];
    wire [7:0] b2a = mem[blk_base + 3*grp + 12'd2];
    wire [7:0] b0b = mem[blk_base + 3*grp + 12'd3];
    wire [7:0] b1b = mem[blk_base + 3*grp + 12'd4];
    wire [7:0] b2b = mem[blk_base + 3*grp + 12'd5];
    wire [7:0] b0c = mem[blk_base + 3*grp + 12'd6];
    wire [7:0] b1c = mem[blk_base + 3*grp + 12'd7];
    wire [7:0] b2c = mem[blk_base + 3*grp + 12'd8];

    wire [11:0] d1a = {b1a[3:0], b0a};
    wire [11:0] d2a = {b2a, b1a[7:4]};
    wire [11:0] d1b = {b1b[3:0], b0b};
    wire [11:0] d2b = {b2b, b1b[7:4]};
    wire [11:0] d1c = {b1c[3:0], b0c};
    wire [11:0] d2c = {b2c, b1c[7:4]};

    wire aw_ok = (3*grp + 12'd3) <= 12'd168;
    wire bw_ok = (3*grp + 12'd6) <= 12'd168;
    wire cw_ok = (3*grp + 12'd9) <= 12'd168;

    wire a1a = aw_ok && d1a < Q;
    wire [8:0] n1a = {1'b0, idx} + (a1a ? 9'd1 : 9'd0);
    wire a2a = aw_ok && d2a < Q && n1a < 9'd256;
    wire [8:0] n2a = n1a + (a2a ? 9'd1 : 9'd0);
    wire a1b = bw_ok && d1b < Q && n2a < 9'd256;
    wire [8:0] n1b = n2a + (a1b ? 9'd1 : 9'd0);
    wire a2b = bw_ok && d2b < Q && n1b < 9'd256;
    wire [8:0] n2b = n1b + (a2b ? 9'd1 : 9'd0);
    wire a1c = cw_ok && d1c < Q && n2b < 9'd256;
    wire [8:0] n1c = n2b + (a1c ? 9'd1 : 9'd0);
    wire a2c = cw_ok && d2c < Q && n1c < 9'd256;
    wire [8:0] n2c = n1c + (a2c ? 9'd1 : 9'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            idx <= 8'd0;
            grp <= 12'd0;
            blk_cnt <= 4'd0;
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
                        grp <= 12'd0;
                        blk_cnt <= 4'd0;
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
                    shk_blk_data <= {rho, i, j, 1072'b0};
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
                            mem[blk_cnt*12'd168 + bb_i] = shk_out_data[1343 - 8*bb_i -: 8];
                        blk_cnt <= blk_cnt + 4'd1;
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (3*grp >= 12'd168) begin
                        if (blk_cnt >= 4'd5) begin
                            if (retry == RETRY_MAX) begin
                                shk_req <= 1'b0;
                                error <= 1'b1;
                                busy <= 1'b0;
                                done <= 1'b1;
                                phase <= PHASE_IDLE;
                            end else begin
                                retry <= retry + 8'd1;
                                grp <= 12'd0;
                                blk_cnt <= 4'd0;
                                shk_req <= 1'b0;
                                phase <= PHASE_RETR;
                            end
                        end else begin
                            grp <= 12'd0;
                            shk_out_ready <= 1'b1;
                            phase <= PHASE_OUT;
                        end
                    end else begin
                        if (a1a) coeffs_arr[idx[7:0]] <= d1a;
                        if (a2a) coeffs_arr[n1a[7:0]] <= d2a;
                        if (a1b) coeffs_arr[n2a[7:0]] <= d1b;
                        if (a2b) coeffs_arr[n1b[7:0]] <= d2b;
                        if (a1c) coeffs_arr[n2b[7:0]] <= d1c;
                        if (a2c) coeffs_arr[n1c[7:0]] <= d2c;
                        idx <= n2c[7:0];
                        if (n2c >= 9'd256) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            grp <= grp + 12'd3;
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
            assign coeffs[12*g +: 12] = coeffs_arr[g];
        end
    endgenerate
endmodule
