module engine_client #(
    parameter NBLK_W = 4,
    parameter DATA_W = 1344
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,
    input  wire [17:0]       cfg,
    input  wire [NBLK_W-1:0] nblk,
    input  wire [DATA_W-1:0] msg_blk,
    input  wire              req_ready,
    input  wire              blk_ready,
    input  wire              out_valid,
    input  wire              done,
    output reg               req_valid,
    output reg               blk_valid,
    output wire [DATA_W-1:0] blk_data,
    output reg               out_ready,
    output reg  [NBLK_W-1:0] blk_idx,
    output wire              out_sync
);
    localparam PHASE_IDLE  = 4'd0;
    localparam PHASE_REQ   = 4'd1;
    localparam PHASE_BLK   = 4'd2;
    localparam PHASE_BLK2  = 4'd3;
    localparam PHASE_BLKW  = 4'd4;
    localparam PHASE_OUTW  = 4'd5;
    localparam PHASE_OUTW2 = 4'd6;
    localparam PHASE_OUTW3 = 4'd7;
    localparam PHASE_DONEW = 4'd8;

    reg [3:0] phase;
    reg [3:0] ob_cnt;

    wire [3:0] out_blocks = cfg[17:14];

    assign blk_data = msg_blk;
    assign out_sync = (phase == PHASE_OUTW) && out_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            req_valid <= 1'b0;
            blk_valid <= 1'b0;
            out_ready <= 1'b0;
            blk_idx <= {NBLK_W{1'b0}};
            ob_cnt <= 4'd0;
        end else begin
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        req_valid <= 1'b1;
                        blk_idx <= {NBLK_W{1'b0}};
                        ob_cnt <= 4'd0;
                        phase <= PHASE_REQ;
                    end
                end
                PHASE_REQ: begin
                    if (req_ready) phase <= PHASE_BLK;
                end
                PHASE_BLK: begin
                    blk_valid <= 1'b1;
                    phase <= PHASE_BLK2;
                end
                PHASE_BLK2: begin
                    if (blk_ready) begin
                        blk_valid <= 1'b0;
                        if (blk_idx + 1 >= nblk) begin
                            phase <= PHASE_OUTW;
                        end else begin
                            blk_idx <= blk_idx + 1;
                            phase <= PHASE_BLKW;
                        end
                    end
                end
                PHASE_BLKW: begin
                    if (blk_ready) phase <= PHASE_BLK;
                end
                PHASE_OUTW: begin
                    if (out_valid) begin
                        out_ready <= 1'b1;
                        if (ob_cnt + 1 >= out_blocks) begin
                            phase <= PHASE_DONEW;
                        end else begin
                            ob_cnt <= ob_cnt + 1;
                            phase <= PHASE_OUTW2;
                        end
                    end
                end
                PHASE_OUTW2: begin
                    if (!out_valid) phase <= PHASE_OUTW3;
                end
                PHASE_OUTW3: begin
                    if (out_valid) begin
                        out_ready <= 1'b1;
                        if (ob_cnt + 1 >= out_blocks) begin
                            phase <= PHASE_DONEW;
                        end else begin
                            ob_cnt <= ob_cnt + 1;
                            phase <= PHASE_OUTW2;
                        end
                    end
                end
                PHASE_DONEW: begin
                    if (done) begin
                        req_valid <= 1'b0;
                        out_ready <= 1'b0;
                        phase <= PHASE_IDLE;
                    end
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end
endmodule
