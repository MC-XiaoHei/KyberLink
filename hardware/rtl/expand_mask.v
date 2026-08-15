module expand_mask (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] rho,
    input  wire [15:0]  mu,
    output reg          busy,
    output reg          done,
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
    localparam GAMMA1 = 20'd524288;

    localparam PHASE_IDLE = 3'd0;
    localparam PHASE_REQ  = 3'd1;
    localparam PHASE_BLK  = 3'd2;
    localparam PHASE_BLK2 = 3'd7;
    localparam PHASE_OUT  = 3'd3;
    localparam PHASE_PROC = 3'd4;
    localparam PHASE_FLUSH = 3'd5;

    reg [22:0] coeffs_arr [0:255];
    reg [7:0]  mem [0:679];
    integer    bb_i;

    reg [2:0]  phase;
    reg [8:0]  p;
    reg [3:0]  blk_cnt;

    assign shk_cfg = {4'd5, 2'd1, 12'd66};

    wire [12:0] base = 13'd20 * {4'd0, p};
    wire [2:0] bo = base[2:0];
    wire [9:0] bi = base[12:3];
    wire [7:0] mv0 = mem[bi];
    wire [7:0] mv1 = mem[bi + 10'd1];
    wire [7:0] mv2 = mem[bi + 10'd2];
    wire [19:0] v = ({12'd0, mv0} >> bo)
                  | ({12'd0, mv1} << (8'd8 - {5'd0, bo}))
                  | ({12'd0, mv2} << (8'd16 - {5'd0, bo}));
    wire [23:0] sumv = {4'd0, GAMMA1} + {1'b0, Q} - {4'd0, v};
    wire [22:0] yv = (sumv >= {1'b0, Q}) ? (sumv[22:0] - Q) : sumv[22:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            p <= 9'd0;
            blk_cnt <= 4'd0;
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
                        p <= 9'd0;
                        blk_cnt <= 4'd0;
                        shk_req <= 1'b1;
                        phase <= PHASE_REQ;
                    end
                end
                PHASE_REQ: begin
                    if (shk_ready) phase <= PHASE_BLK;
                end
                PHASE_BLK: begin
                    shk_blk_valid <= 1'b1;
                    shk_blk_data <= {256'b0, rho, mu[7:0], mu[15:8], 560'b0};
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
                        blk_cnt <= blk_cnt + 4'd1;
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (bi >= blk_cnt * 9'd136 - 9'd3) begin
                        shk_out_ready <= 1'b1;
                        phase <= PHASE_OUT;
                    end else begin
                        coeffs_arr[p[7:0]] <= yv;
                        if (p == 9'd255) begin
                            phase <= PHASE_FLUSH;
                        end else begin
                            p <= p + 9'd1;
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
