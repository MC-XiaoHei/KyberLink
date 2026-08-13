module ghash (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [127:0] h,
    input  wire [127:0] data_in,
    input  wire data_valid,
    input  wire [7:0] nblocks,
    output reg busy,
    output reg done,
    output wire [127:0] tag
);

    localparam PHASE_IDLE = 2'd0;
    localparam PHASE_WAIT = 2'd1;
    localparam PHASE_MUL  = 2'd2;

    reg [1:0] phase;
    reg [127:0] hshift;
    reg [127:0] xreg;
    reg [127:0] acc;
    reg [127:0] yacc;
    reg [7:0] blk;
    reg [7:0] cnt;
    wire [127:0] acc_next = xreg[0] ? (acc ^ hshift) : acc;

    genvar gi;
    wire [127:0] h_rev;
    wire [127:0] d_rev;
    generate
        for (gi = 0; gi < 128; gi = gi + 1) begin : grev_h
            assign h_rev[gi] = h[127-gi];
        end
        for (gi = 0; gi < 128; gi = gi + 1) begin : grev_d
            assign d_rev[gi] = data_in[127-gi];
        end
        for (gi = 0; gi < 128; gi = gi + 1) begin : grev_t
            assign tag[gi] = yacc[127-gi];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= PHASE_IDLE;
            busy  <= 1'b0;
            done  <= 1'b0;
            yacc  <= 128'd0;
        end else begin
            done <= 1'b0;
            case (phase)
                PHASE_IDLE: begin
                    if (start) begin
                        busy   <= 1'b1;
                        hshift <= h_rev;
                        yacc   <= 128'd0;
                        blk    <= nblocks;
                        phase  <= PHASE_WAIT;
                    end
                end
                PHASE_WAIT: begin
                    if (data_valid) begin
                        xreg  <= yacc ^ d_rev;
                        hshift <= h_rev;
                        acc   <= 128'd0;
                        cnt   <= 8'd0;
                        phase <= PHASE_MUL;
                    end
                end
                PHASE_MUL: begin
                    if (cnt == 8'd127) begin
                        if (blk == 8'd1) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            phase <= PHASE_IDLE;
                        end else begin
                            blk   <= blk - 8'd1;
                            phase <= PHASE_WAIT;
                        end
                        yacc <= acc_next;
                    end else begin
                        cnt <= cnt + 8'd1;
                    end
                    acc  <= acc_next;
                    xreg <= xreg >> 1;
                    if (hshift[127]) hshift <= (hshift << 1) ^ 128'h87;
                    else             hshift <= hshift << 1;
                end
                default: phase <= PHASE_IDLE;
            endcase
        end
    end

endmodule
