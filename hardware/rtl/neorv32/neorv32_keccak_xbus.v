// NEORV32 XBUS Keccak-f[1600] 加速外设
// 协议：软核管理填充/拼接，外设做块置换（rate 字节缓冲满 -> 24 轮置换 -> squeeze）
// 寄存器（字节地址）：
//   0x00 CTRL:   [3:0] mode (0=SHAKE128 1=SHAKE256 2=SHA3-256 3=SHA3-512), [4] start
//   0x04 STATUS: [0] busy, [1] blk_done (置换完成，写 1 清)
//   0x08 DATA0:  数据低 32bit (写=absorb, 读=squeeze)
//   0x0C DATA1:  数据高 32bit
// 软件流程（absorb）：写 CTRL(mode|start) -> 写 rate/8 个 64-bit 到 DATA -> 等 busy 下降
//               -> 重复下一块；squeeze：切模式后逐 64-bit 读 DATA
module neorv32_keccak_xbus (
    input  wire        clk,
    input  wire        rst_n,
    // XBUS slave (NEORV32 external bus)
    input  wire [31:0] xbus_adr_i,
    input  wire [31:0] xbus_dat_i,
    input  wire        xbus_we_i,
    input  wire        xbus_stb_i,
    input  wire        xbus_cyc_i,
    output reg  [31:0] xbus_dat_o,
    output reg         xbus_ack_o,
    output reg         xbus_err_o,
    // Keccak round function (combinational)
    output wire [1599:0] perm_state_in,
    output wire [4:0]    perm_round,
    input  wire [1599:0] perm_state_out
);

    localparam MODE_SHAKE128 = 3'd0;
    localparam MODE_SHAKE256 = 3'd1;
    localparam MODE_SHA3_256 = 3'd2;
    localparam MODE_SHA3_512 = 3'd3;

    wire [3:0] mode = cfg_mode;
    reg  [3:0] cfg_mode;
    reg        start;
    reg  [1:0] state;
    localparam ST_IDLE = 2'd0, ST_ABS = 2'd1, ST_PERM = 2'd2, ST_SQZ = 2'd3;

    reg  [1599:0] state_reg;      // Keccak state (absorb buffer + squeeze out)
    assign perm_state_in = state_reg;
    assign perm_round = round_cnt;
    reg  [7:0]    word_cnt;       // 64-bit words buffered (0..rate/8)
    reg  [4:0]    round_cnt;      // permutation rounds 0..23
    reg          busy;
    reg          blk_done;

    // rate in bytes per mode
    wire [7:0] rate_bytes =
        (cfg_mode == MODE_SHAKE128) ? 8'd168 :
        (cfg_mode == MODE_SHAKE256) ? 8'd136 :
        (cfg_mode == MODE_SHA3_256) ? 8'd136 :
                                     8'd72;

    wire xbus_active = xbus_stb_i && xbus_cyc_i && (xbus_adr_i[31:8] == 24'hF00000);
    wire [3:0] reg_sel = xbus_adr_i[7:0];
    wire is_write = xbus_we_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_mode <= 4'd0;
            start <= 1'b0;
            state <= ST_IDLE;
            state_reg <= 1600'd0;
            word_cnt <= 8'd0;
            round_cnt <= 5'd0;
            busy <= 1'b0;
            blk_done <= 1'b0;
            xbus_dat_o <= 32'd0;
            xbus_ack_o <= 1'b0;
            xbus_err_o <= 1'b0;
        end else begin
            xbus_ack_o <= 1'b0;
            xbus_err_o <= 1'b0;
            start <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (xbus_active && is_write && reg_sel == 8'h00) begin
                        cfg_mode <= xbus_dat_i[3:0];
                        start <= xbus_dat_i[4];
                    end
                    if (start) begin
                        state <= ST_ABS;
                        word_cnt <= 8'd0;
                        busy <= 1'b1;
                    end
                end
                ST_ABS: begin
                    if (xbus_active && is_write && (reg_sel == 8'h08 || reg_sel == 8'h0C)) begin
                        // write 64-bit word into state buffer at word_cnt
                        if (reg_sel == 8'h08)
                            state_reg[64*word_cnt +: 32] <= state_reg[64*word_cnt +: 32] ^ xbus_dat_i;
                        else begin
                            state_reg[64*word_cnt + 32 +: 32] <= state_reg[64*word_cnt + 32 +: 32] ^ xbus_dat_i;
                            word_cnt <= word_cnt + 8'd1;
                            if (word_cnt + 8'd1 >= (rate_bytes >> 3)) begin
                                state <= ST_PERM;
                                round_cnt <= 5'd0;
                            end
                        end
                    end
                end
                ST_PERM: begin
                    state_reg <= perm_state_out;
                    if (round_cnt == 5'd23) begin
                        state <= ST_SQZ;
                        word_cnt <= 8'd0;
                        blk_done <= 1'b1;
                    end else begin
                        round_cnt <= round_cnt + 5'd1;
                    end
                end
                ST_SQZ: begin
                    if (xbus_active && is_write && reg_sel == 8'h00) begin
                        if (xbus_dat_i[4]) begin
                            state <= ST_ABS;
                            word_cnt <= 8'd0;
                        end else begin
                            state <= ST_IDLE;
                            busy <= 1'b0;
                        end
                    end else if (xbus_active && is_write && reg_sel == 8'h04) begin
                        blk_done <= 1'b0;
                    end else if (xbus_active && !is_write && (reg_sel == 8'h08 || reg_sel == 8'h0C)) begin
                        if (reg_sel == 8'h0C) begin
                            word_cnt <= word_cnt + 8'd1;
                            if (word_cnt + 8'd1 >= (rate_bytes >> 3)) begin
                                state <= ST_PERM;
                                round_cnt <= 5'd0;
                                busy <= 1'b1;
                            end
                        end
                    end
                end
            endcase

            // read data
            if (xbus_active && !is_write) begin
                case (reg_sel)
                    8'h00: xbus_dat_o <= {28'd0, cfg_mode};
                    8'h04: xbus_dat_o <= {30'd0, blk_done, busy};
                    8'h08: xbus_dat_o <= state_reg[64*word_cnt +: 32];
                    8'h0C: xbus_dat_o <= state_reg[64*word_cnt + 32 +: 32];
                    default: begin
                        xbus_dat_o <= 32'd0;
                        xbus_err_o <= 1'b1;
                    end
                endcase
                xbus_ack_o <= 1'b1;
            end else if (xbus_active && is_write) begin
                case (reg_sel)
                    8'h00, 8'h04, 8'h08, 8'h0C: xbus_ack_o <= 1'b1;
                    default: xbus_err_o <= 1'b1;
                endcase
            end
        end
    end
endmodule
