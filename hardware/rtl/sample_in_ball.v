module sample_in_ball (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [383:0] ctilde,
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
    localparam TAU = 8'd49;
    localparam JPOS_MAX = 12'd2048;

    localparam PHASE_IDLE = 3'd0;
    localparam PHASE_REQ  = 3'd1;
    localparam PHASE_BLK  = 3'd2;
    localparam PHASE_BLK2 = 3'd3;
    localparam PHASE_OUT  = 3'd4;
    localparam PHASE_PROC = 3'd5;
    localparam PHASE_FLUSH = 3'd6;

    reg [22:0] coeffs_arr [0:255];
    integer    ci;

    reg [2:0]    phase;
    reg [1087:0] blk0;
    reg [1087:0] blk1;
    reg [7:0]    i_idx;
    reg [7:0]    i_cnt;
    reg [11:0]   jpos;
    reg          has_blk1;
    reg          err_pending;

    assign shk_cfg = {4'd2, 2'd1, 12'd48};

    wire [11:0]  jb_sub = jpos - 12'd136;
    wire [7:0] jb = (jpos < 12'd136) ? blk0[1087 - 8*jpos[7:0] -: 8]
                                     : blk1[1087 - 8*jb_sub[7:0] -: 8];
    wire accept = jb <= i_idx;
    wire [7:0] sbit_off = i_idx - 8'd207;
    wire [2:0] sbyte_off = sbit_off[5:3];
    wire [7:0] sbyte = blk0[1087 - 8*sbyte_off -: 8];
    wire bitv = sbyte[sbit_off[2:0]];
    wire [22:0] cj = bitv ? (Q - 23'd1) : 23'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            i_idx <= 8'd207;
            i_cnt <= 8'd0;
            jpos <= 12'd0;
            error <= 1'b0;
            shk_req <= 1'b0;
            shk_blk_valid <= 1'b0;
            shk_out_ready <= 1'b0;
            shk_blk_data <= 1344'b0;
            has_blk1 <= 1'b0;
            err_pending <= 1'b0;
        end else begin
            done <= 1'b0;
            shk_out_ready <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        i_idx <= 8'd207;
                        i_cnt <= 8'd0;
                        jpos <= 12'd8;
                        error <= 1'b0;
                        err_pending <= 1'b0;
                        has_blk1 <= 1'b0;
                        for (ci = 0; ci < 256; ci = ci + 1) coeffs_arr[ci] = 23'd0;
                        shk_req <= 1'b1;
                        phase <= PHASE_REQ;
                    end
                end
                PHASE_REQ: begin
                    if (shk_ready) phase <= PHASE_BLK;
                end
                PHASE_BLK: begin
                    shk_blk_valid <= 1'b1;
                    shk_blk_data <= {256'b0, ctilde, 704'b0};
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
                        phase <= PHASE_PROC;
                    end
                end
                PHASE_PROC: begin
                    if (!has_blk1 && shk_out_valid) begin
                        blk1 <= shk_out_data[1087:0];
                        has_blk1 <= 1'b1;
                        shk_out_ready <= 1'b1;
                    end
                    if (accept) begin
                        coeffs_arr[i_idx] <= coeffs_arr[jb[7:0]];
                        coeffs_arr[jb[7:0]] <= cj;
                        i_idx <= i_idx + 8'd1;
                        i_cnt <= i_cnt + 8'd1;
                    end
                    jpos <= jpos + 12'd1;
                    if (jpos == JPOS_MAX) begin
                        err_pending <= 1'b1;
                        phase <= PHASE_FLUSH;
                    end else if (i_cnt == TAU - 8'd1 && accept) begin
                        phase <= PHASE_FLUSH;
                    end
                end
                PHASE_FLUSH: begin
                    if (shk_out_valid) shk_out_ready <= 1'b1;
                    if (shk_done) begin
                        shk_req <= 1'b0;
                        if (err_pending) error <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        err_pending <= 1'b0;
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
